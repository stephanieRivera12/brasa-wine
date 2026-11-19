/* spawner.exe [--app] [--repeat N] [--pad N] <child> [args...]
 *
 * Starts <child> with CreateProcessW and waits for it. The line is "<child>" followed by the raw
 * args, then --pad N as one more argument of N 'a' (for lines too long to pass as arguments);
 * --app also passes <child> as lpApplicationName. With --app and nothing after <child>
 * the line is empty. --repeat N runs the child N times and
 * prints the total milliseconds (QueryPerformanceCounter). */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#define PAD_CHAR L'a'
#define EXIT_USAGE 2
#define EXIT_NO_MEMORY 3
#define EXIT_CREATE_FAILED 4
#define MS_PER_SECOND 1000LL

struct options
{
    BOOL use_app_name;
    int repeat;
    int pad_chars;
    const WCHAR *child;
    int first_arg;
};

static BOOL parse_options( int argc, WCHAR **argv, struct options *opt )
{
    int i = 1;

    memset( opt, 0, sizeof(*opt) );
    opt->repeat = 1;
    for (; i < argc; i++)
    {
        if (!wcscmp( argv[i], L"--app" )) opt->use_app_name = TRUE;
        else if (!wcscmp( argv[i], L"--repeat" ) && i + 1 < argc) opt->repeat = _wtoi( argv[++i] );
        else if (!wcscmp( argv[i], L"--pad" ) && i + 1 < argc) opt->pad_chars = _wtoi( argv[++i] );
        else break;
    }
    if (i >= argc || opt->repeat < 1 || opt->pad_chars < 0) return FALSE;
    opt->child = argv[i];
    opt->first_arg = i + 1;
    return TRUE;
}

static WCHAR *build_line( int argc, WCHAR **argv, const struct options *opt )
{
    size_t size = wcslen( opt->child ) + 3 + opt->pad_chars + 2;
    WCHAR *line;
    int i;

    for (i = opt->first_arg; i < argc; i++) size += wcslen( argv[i] ) + 1;
    if (!(line = malloc( size * sizeof(WCHAR) ))) return NULL;
    swprintf( line, size, L"\"%ls\"", opt->child );
    for (i = opt->first_arg; i < argc; i++) swprintf( line + wcslen( line ), size, L" %ls", argv[i] );
    if (opt->pad_chars)
    {
        size_t length = wcslen( line );
        line[length++] = L' ';
        wmemset( line + length, PAD_CHAR, opt->pad_chars );
        line[length + opt->pad_chars] = 0;
    }
    return line;
}

static BOOL run_child( const struct options *opt, WCHAR *line )
{
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;

    memset( &si, 0, sizeof(si) );
    si.cb = sizeof(si);

    if (!CreateProcessW( opt->use_app_name ? opt->child : NULL, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi ))
        return FALSE;
    WaitForSingleObject( pi.hProcess, INFINITE );
    CloseHandle( pi.hThread );
    CloseHandle( pi.hProcess );
    return TRUE;
}

int wmain( int argc, WCHAR **argv )
{
    struct options opt;
    LARGE_INTEGER freq, start, end;
    WCHAR *line;
    int i;

    if (!parse_options( argc, argv, &opt )) return EXIT_USAGE;
    line = build_line( argc, argv, &opt );
    if (!line) return EXIT_NO_MEMORY;
    if (opt.use_app_name && opt.first_arg == argc && !opt.pad_chars) line[0] = 0;

    QueryPerformanceFrequency( &freq );
    QueryPerformanceCounter( &start );
    for (i = 0; i < opt.repeat; i++)
    {
        /* CreateProcessW may write into the line: give it a fresh copy each time */
        WCHAR *copy = _wcsdup( line );
        BOOL ok = copy && run_child( &opt, copy );
        free( copy );
        if (!ok) return EXIT_CREATE_FAILED;
    }
    QueryPerformanceCounter( &end );
    if (opt.repeat > 1)
        printf( "%lld\n", (end.QuadPart - start.QuadPart) * MS_PER_SECOND / freq.QuadPart );
    free( line );
    return 0;
}
