#include <errno.h>
#include <jni.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

/* Native local HTTP proxy. No certificate interception or root calls.
 * Uses pinned MIT-licensed hufrea/ByeDPI C source for DPI fragmentation. */
/* Native daemon mode must never fork or outlive its own Android service. */
int __wrap_daemon(int nochdir, int noclose) {
    (void)nochdir; (void)noclose;
    errno = EPERM;
    return -1;
}

extern int main(int argc, char **argv);
extern int server_fd;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static int started = 0;
static int running = 0;

JNIEXPORT jint JNICALL
Java_com_sopo9880_hyp_1viewer_DpiNativeBridge_run(
    JNIEnv *env, jobject obj, jobjectArray args) {
    (void)obj;
    pthread_mutex_lock(&mutex);
    if (started) {
        pthread_mutex_unlock(&mutex);
        return -1;
    }
    started = 1;
    pthread_mutex_unlock(&mutex);
    int count = (*env)->GetArrayLength(env, args);
    if (count < 1 || count > 24) return -1;
    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (!argv) return -1;
    int result = -1;
    for (int i = 0; i < count; i++) {
        jstring arg = (jstring)(*env)->GetObjectArrayElement(env, args, i);
        if (!arg) goto cleanup;
        const char *value = (*env)->GetStringUTFChars(env, arg, NULL);
        if (!value) {
            (*env)->DeleteLocalRef(env, arg);
            goto cleanup;
        }
        argv[i] = strdup(value);
        (*env)->ReleaseStringUTFChars(env, arg, value);
        (*env)->DeleteLocalRef(env, arg);
        if (!argv[i]) goto cleanup;
    }
    pthread_mutex_lock(&mutex);
    server_fd = -1;
    running = 1;
    pthread_mutex_unlock(&mutex);
    result = main(count, argv);
    pthread_mutex_lock(&mutex);
    running = 0;
    pthread_mutex_unlock(&mutex);
cleanup:
    for (int i = 0; i < count; i++) free(argv[i]);
    free(argv);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_sopo9880_hyp_1viewer_DpiNativeBridge_stop(
    JNIEnv *env, jobject obj) {
    (void)env;
    (void)obj;
    pthread_mutex_lock(&mutex);
    int result = running && server_fd >= 0
        ? shutdown(server_fd, SHUT_RDWR) : -1;
    pthread_mutex_unlock(&mutex);
    return result;
}
