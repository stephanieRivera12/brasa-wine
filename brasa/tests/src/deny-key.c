/* Writes the value steamwebhelper.exe under HKCU\Software\Brasa\AppendCommandLine, then replaces
 * the key's DACL with an empty one: nobody, the owner included, can read it afterwards. Used by
 * the unreadableKey case, because regedit cannot set an ACL. Prints nothing; exit 0 on success. */
#include <windows.h>
#include <aclapi.h>

#define KEY_PATH L"Software\\Brasa\\AppendCommandLine"
#define VALUE_NAME L"steamwebhelper.exe"
#define VALUE_DATA L"--no-sandbox --in-process-gpu --disable-gpu"
#define EXIT_REG_FAILED 2
#define EXIT_ACL_FAILED 3

static BOOL deny_all( HKEY key )
{
    ACL acl;
    SECURITY_DESCRIPTOR sd;

    return InitializeAcl( &acl, sizeof(acl), ACL_REVISION )
        && InitializeSecurityDescriptor( &sd, SECURITY_DESCRIPTOR_REVISION )
        && SetSecurityDescriptorDacl( &sd, TRUE, &acl, FALSE )
        && RegSetKeySecurity( key, DACL_SECURITY_INFORMATION, &sd ) == ERROR_SUCCESS;
}

int wmain( void )
{
    HKEY key;
    LSTATUS status = RegCreateKeyExW( HKEY_CURRENT_USER, KEY_PATH, 0, NULL, 0, KEY_ALL_ACCESS, NULL, &key, NULL );

    if (status != ERROR_SUCCESS) return EXIT_REG_FAILED;
    status = RegSetValueExW( key, VALUE_NAME, 0, REG_SZ, (const BYTE *)VALUE_DATA, sizeof(VALUE_DATA) );
    if (status != ERROR_SUCCESS) return EXIT_REG_FAILED;
    status = deny_all( key ) ? ERROR_SUCCESS : ERROR_ACCESS_DENIED;
    RegCloseKey( key );
    return status == ERROR_SUCCESS ? 0 : EXIT_ACL_FAILED;
}
