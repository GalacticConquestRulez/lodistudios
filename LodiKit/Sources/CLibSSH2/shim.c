// Intentionally empty. CLibSSH2 is a header shim that re-exports the libssh2
// public headers as a Swift-importable module; all symbols are provided by the
// vendored libssh2 static-library xcframework it links against. This translation
// unit exists only so SwiftPM treats CLibSSH2 as a buildable C target.
#include "shim.h"
