/* Writes its own command line, as UTF-8 and without a newline, to the file named by BRASA_TEST_OUT. */
#include <windows.h>
#include <stdio.h>

#define OUT_ENV_NAME L"BRASA_TEST_OUT"
#define MAX_OUT_PATH 4096
#define EXIT_NO_OUT_FILE 2
#define EXIT_WRITE_FAILED 3

static char *to_utf8( const WCHAR *text, int *length )
{
    int size = WideCharToMultiByte( CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL );
    char *buffer = size > 0 ? HeapAlloc( GetProcessHeap(), 0, size ) : NULL;

    if (!buffer || !WideCharToMultiByte( CP_UTF8, 0, text, -1, buffer, size, NULL, NULL )) return NULL;
    *length = size - 1;
    return buffer;
}

int wmain( void )
{
    WCHAR out_path[MAX_OUT_PATH];
    DWORD written, got = GetEnvironmentVariableW( OUT_ENV_NAME, out_path, MAX_OUT_PATH );
    int length;
    char *line = to_utf8( GetCommandLineW(), &length );
    HANDLE file;
    BOOL ok;

    if (!got || got >= MAX_OUT_PATH) return EXIT_NO_OUT_FILE;
    if (!line) return EXIT_WRITE_FAILED;
    file = CreateFileW( out_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL );
    if (file == INVALID_HANDLE_VALUE) return EXIT_WRITE_FAILED;
    ok = WriteFile( file, line, length, &written, NULL ) && written == (DWORD)length;
    CloseHandle( file );
    return ok ? 0 : EXIT_WRITE_FAILED;
}
