// Marker header: this target only exists to compile the SQLite amalgamation into the image, so that GRDB's
// sqlite3_* references bind to this copy instead of the (older) /usr/lib/libsqlite3.dylib.
#include "sqlite3.h"
