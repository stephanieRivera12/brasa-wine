/*
 * Brasa: constants of the per-program command-line options (brasa_cmdline.c).
 * Spec 5.1; the same limits are mirrored in brasa/tests/test-constants.sh.
 */

#ifndef __WINE_KERNELBASE_BRASA_CONSTANTS_H
#define __WINE_KERNELBASE_BRASA_CONSTANTS_H

/* Under HKCU: one value per program, name = exe file name, data = the options (REG_SZ). */
#define BRASA_APPEND_KEY            L"Software\\Brasa\\AppendCommandLine"
#define BRASA_MAX_OPTIONS_CHARS     1024
#define BRASA_MAX_CMDLINE_CHARS     32767   /* Windows limit of a command line */
#define BRASA_OPTIONS_SEPARATOR     L" "
#define BRASA_FIRST_PRINTABLE_CHAR  0x20
#define BRASA_DELETE_CHAR           0x7f

#endif /* __WINE_KERNELBASE_BRASA_CONSTANTS_H */
