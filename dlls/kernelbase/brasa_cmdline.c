/*
 * Brasa: per-program extra command-line options
 *
 * HKCU\Software\Brasa\AppendCommandLine holds one REG_SZ value per program: the name is the exe
 * file name, the data the options appended to the command line of every process created from that
 * exe (CreateProcess and everything built on it). Used to start Steam's web helper with the flags
 * it needs under Wine.
 *
 * Trust model (spec 5.1): the key lives in the private Wine prefix Brasa creates. Any program in
 * that prefix could write it, but it already runs code in the same prefix, so this grants no new
 * permission. Even so, a bad value is never trusted: it is ignored (the line stays as it was and
 * the program starts anyway), with a warning in the "brasa" channel that names the exe and the
 * reason, never the data or the command line, which may hold user paths.
 */

#include <stdarg.h>
#include <string.h>

#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winbase.h"
#include "winreg.h"
#include "winternl.h"

#include "kernelbase.h"
#include "brasa_cmdline.h"
#include "brasa_constants.h"
#include "wine/debug.h"

WINE_DECLARE_DEBUG_CHANNEL(brasa);

enum options_status
{
    OPTIONS_VALID,
    OPTIONS_WRONG_TYPE,
    OPTIONS_EMPTY,
    OPTIONS_TOO_LONG,
    OPTIONS_EMBEDDED_NUL,
    OPTIONS_CONTROL_CHAR,
    OPTIONS_RESULT_TOO_LONG,
};

static const char *options_status_text( enum options_status status )
{
    switch (status)
    {
    case OPTIONS_VALID:           return "valid";
    case OPTIONS_WRONG_TYPE:      return "value is not REG_SZ";
    case OPTIONS_EMPTY:           return "value is empty";
    case OPTIONS_TOO_LONG:        return "value is too long";
    case OPTIONS_EMBEDDED_NUL:    return "value has an embedded NUL";
    case OPTIONS_CONTROL_CHAR:    return "value has a control character";
    case OPTIONS_RESULT_TOO_LONG: return "resulting command line is too long";
    }
    return "unknown";
}

static BOOL is_control_char( WCHAR ch )
{
    return ch < BRASA_FIRST_PRINTABLE_CHAR || ch == BRASA_DELETE_CHAR;
}

static BOOL has_control_char( const WCHAR *text, SIZE_T length )
{
    SIZE_T i;

    for (i = 0; i < length; i++)
        if (is_control_char( text[i] )) return TRUE;
    return FALSE;
}

/* Pure: judges a value read from the registry. size is in bytes and includes the terminator;
 * cmdline_length is the length in characters of the line the options would be appended to. */
static enum options_status validate_options( DWORD type, const WCHAR *data, DWORD size, SIZE_T cmdline_length )
{
    SIZE_T length;

    if (type != REG_SZ) return OPTIONS_WRONG_TYPE;
    if (size < sizeof(WCHAR) || size % sizeof(WCHAR)) return OPTIONS_EMBEDDED_NUL;
    length = size / sizeof(WCHAR) - 1;
    if (!length) return OPTIONS_EMPTY;
    if (length > BRASA_MAX_OPTIONS_CHARS) return OPTIONS_TOO_LONG;
    if (data[length] || wcslen( data ) != length) return OPTIONS_EMBEDDED_NUL;
    if (has_control_char( data, length )) return OPTIONS_CONTROL_CHAR;
    if (cmdline_length + wcslen( BRASA_OPTIONS_SEPARATOR ) + length > BRASA_MAX_CMDLINE_CHARS)
        return OPTIONS_RESULT_TOO_LONG;
    return OPTIONS_VALID;
}

/* The file name of the program: what follows the last backslash or slash. */
static const WCHAR *program_name( const WCHAR *path )
{
    const WCHAR *name = path, *p;

    for (p = path; *p; p++)
        if (*p == '\\' || *p == '/') name = p + 1;
    return name;
}

/* Reads the options of a program; returns the reason they are not usable (silently for
 * "no value" and unreadable keys: those are the normal "no options" case). */
static enum options_status read_options( const WCHAR *name, WCHAR *buffer, DWORD *size, SIZE_T cmdline_length,
                                         BOOL *found )
{
    DWORD type = REG_NONE;
    LSTATUS ret = RegGetValueW( HKEY_CURRENT_USER, BRASA_APPEND_KEY, name, RRF_RT_ANY | RRF_NOEXPAND,
                                &type, buffer, size );

    *found = (ret == ERROR_SUCCESS || ret == ERROR_MORE_DATA);
    if (ret == ERROR_MORE_DATA) return OPTIONS_TOO_LONG;
    if (ret != ERROR_SUCCESS) return OPTIONS_VALID;
    return validate_options( type, buffer, *size, cmdline_length );
}

static WCHAR *join_options( const WCHAR *cmdline, const WCHAR *options )
{
    SIZE_T cmdline_length = wcslen( cmdline ), options_length = wcslen( options );
    SIZE_T total = cmdline_length + wcslen( BRASA_OPTIONS_SEPARATOR ) + options_length + 1;
    WCHAR *line = RtlAllocateHeap( GetProcessHeap(), 0, total * sizeof(WCHAR) );

    if (!line) return NULL;
    memcpy( line, cmdline, cmdline_length * sizeof(WCHAR) );
    wcscpy( line + cmdline_length, BRASA_OPTIONS_SEPARATOR );
    wcscpy( line + cmdline_length + wcslen( BRASA_OPTIONS_SEPARATOR ), options );
    return line;
}

WCHAR *brasa_append_command_line( const WCHAR *app_name, WCHAR *cmdline, const WCHAR *caller_cmdline )
{
    WCHAR options[BRASA_MAX_OPTIONS_CHARS + 1];
    DWORD size = sizeof(options);
    const WCHAR *name;
    enum options_status status;
    BOOL found;
    WCHAR *line;

    if (!app_name || !cmdline) return cmdline;
    name = program_name( app_name );
    if (!*name) return cmdline;

    status = read_options( name, options, &size, wcslen( cmdline ), &found );
    if (status != OPTIONS_VALID)
    {
        WARN_(brasa)( "ignoring the options of %s: %s\n", debugstr_w(name), options_status_text( status ));
        return cmdline;
    }
    if (!found) return cmdline;

    if (!(line = join_options( cmdline, options ))) return cmdline;
    if (cmdline != caller_cmdline) RtlFreeHeap( GetProcessHeap(), 0, cmdline );
    return line;
}
