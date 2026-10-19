package com.sopo9880.hyp_viewer

/** JNI boundary for the pinned MIT-licensed hufrea/ByeDPI local proxy. */
class DpiNativeBridge {
    companion object {
        init {
            System.loadLibrary("hyp_byedpi")
        }
    }

    external fun run(args: Array<String>): Int
    external fun stop(): Int
}
