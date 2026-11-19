/*
 * Brasa: per-program extra command-line options (see brasa_cmdline.c).
 */

#ifndef __WINE_KERNELBASE_BRASA_CMDLINE_H
#define __WINE_KERNELBASE_BRASA_CMDLINE_H

/* Returns cmdline untouched, or a new line (heap of the process) with the options registered for
 * the program app_name appended; then, if cmdline != caller_cmdline, cmdline is freed. Never
 * returns NULL for a non-NULL cmdline and never fails. */
WCHAR *brasa_append_command_line( const WCHAR *app_name, WCHAR *cmdline, const WCHAR *caller_cmdline );

#endif /* __WINE_KERNELBASE_BRASA_CMDLINE_H */
