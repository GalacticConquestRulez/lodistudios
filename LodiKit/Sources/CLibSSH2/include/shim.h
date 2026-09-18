// CLibSSH2 — Swift-facing shim for the vendored libssh2 static-library xcframework.
//
// Swift cannot `import` a static-library binary target directly, so this small C
// target wraps it: the module map below exports these headers as the `CLibSSH2`
// module. The actual declarations come from the libssh2 public headers carried
// inside Vendor/libssh2.xcframework (exposed on the header search path by the
// `libssh2` binary target this target depends on).
#ifndef LODI_CLIBSSH2_SHIM_H
#define LODI_CLIBSSH2_SHIM_H

#include <libssh2.h>
#include <libssh2_sftp.h>
#include <libssh2_publickey.h>

#endif /* LODI_CLIBSSH2_SHIM_H */
