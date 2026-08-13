#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <sys/event.h>
#endif

#if defined(__linux__)
#include <sys/prctl.h>
#endif

static volatile sig_atomic_t pending_termination_signal = 0;
static volatile sig_atomic_t pending_stop = 0;
static volatile sig_atomic_t pending_continue = 0;

static void record_signal(int signal_number) {
    if (signal_number == SIGTSTP) {
        pending_stop = 1;
    } else if (signal_number == SIGCONT) {
        pending_continue = 1;
    } else if (pending_termination_signal == 0) {
        pending_termination_signal = signal_number;
    }
}

static int install_handler(int signal_number) {
    struct sigaction action;
    action.sa_handler = record_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    return sigaction(signal_number, &action, NULL);
}

static void restore_default_handlers(void) {
    int signals[] = {SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGTSTP, SIGCONT};
    struct sigaction action;
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); index++) {
        (void)sigaction(signals[index], &action, NULL);
    }
}

static void sleep_milliseconds(long milliseconds) {
    struct timespec duration;
    duration.tv_sec = milliseconds / 1000;
    duration.tv_nsec = (milliseconds % 1000) * 1000000L;
    while (nanosleep(&duration, &duration) != 0 && errno == EINTR) {
    }
}

static int exit_code_for_status(int status) {
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 125;
}

static int child_is_waitable(pid_t child) {
    siginfo_t info = {0};
    int result;
    do {
        result = waitid(P_PID, (id_t)child, &info, WEXITED | WNOHANG | WNOWAIT);
    } while (result != 0 && errno == EINTR);
    return result == 0 && info.si_pid == child;
}

static int reap_child(pid_t child, int *status) {
    pid_t result;
    do {
        result = waitpid(child, status, 0);
    } while (result < 0 && errno == EINTR);
    return result == child;
}

static int terminate_group(pid_t child, int signal_number) {
    int status = 0;
    int forwarded = signal_number;
    if (forwarded != SIGINT && forwarded != SIGHUP && forwarded != SIGQUIT) {
        forwarded = SIGTERM;
    }
    (void)kill(-child, SIGCONT);
    (void)kill(-child, forwarded);

    for (int attempt = 0; attempt < 20; attempt++) {
        if (child_is_waitable(child)) {
            (void)kill(-child, SIGKILL);
            (void)reap_child(child, &status);
            return 128 + signal_number;
        }
        sleep_milliseconds(25);
    }

    (void)kill(-child, SIGKILL);
    (void)reap_child(child, &status);
    return 128 + signal_number;
}

static int handle_pending_signal(pid_t child) {
    int signal_number = pending_termination_signal;
    if (signal_number != 0) {
        pending_termination_signal = 0;
        return terminate_group(child, signal_number);
    }
    if (pending_stop) {
        pending_stop = 0;
        (void)kill(-child, SIGSTOP);
    }
    if (pending_continue) {
        pending_continue = 0;
        (void)kill(-child, SIGCONT);
    }
    return 0;
}

static int finish_normally(pid_t child) {
    int status = 0;
    (void)kill(-child, SIGTERM);
    sleep_milliseconds(50);
    (void)kill(-child, SIGKILL);
    if (!reap_child(child, &status)) {
        return 125;
    }
    return exit_code_for_status(status);
}

static int monitor_with_polling(pid_t parent, pid_t child) {
    for (;;) {
        if (child_is_waitable(child)) {
            return finish_normally(child);
        }
        int signal_result = handle_pending_signal(child);
        if (signal_result != 0) {
            return signal_result;
        }
        if (getppid() != parent) {
            return terminate_group(child, SIGTERM);
        }
        sleep_milliseconds(50);
    }
}

#if defined(__APPLE__)
static int monitor_with_kqueue(pid_t parent, pid_t child) {
    int queue = kqueue();
    if (queue < 0) {
        return monitor_with_polling(parent, child);
    }

    struct kevent registrations[2];
    EV_SET(&registrations[0], parent, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    EV_SET(&registrations[1], child, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (kevent(queue, registrations, 2, NULL, 0, NULL) != 0) {
        close(queue);
        return monitor_with_polling(parent, child);
    }

    for (;;) {
        if (child_is_waitable(child)) {
            close(queue);
            return finish_normally(child);
        }
        int signal_result = handle_pending_signal(child);
        if (signal_result != 0) {
            close(queue);
            return signal_result;
        }
        if (getppid() != parent) {
            close(queue);
            return terminate_group(child, SIGTERM);
        }

        struct kevent event;
        int event_count = kevent(queue, NULL, 0, &event, 1, NULL);
        if (event_count < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(queue);
            return monitor_with_polling(parent, child);
        }
        if (event_count == 1 && (pid_t)event.ident == parent) {
            close(queue);
            return terminate_group(child, SIGTERM);
        }
    }
}
#endif

int main(int argc, char *argv[]) {
    if (argc < 2 || argv[1][0] != '/') {
        fprintf(stderr, "usage: quill-code-process-supervisor /absolute/executable [arguments...]\n");
        return 64;
    }

    pid_t parent = getppid();
    if (parent <= 1) {
        fprintf(stderr, "quill-code process supervisor has no live parent\n");
        return 125;
    }

#if defined(__linux__)
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) {
        perror("quill-code process supervisor prctl");
        return 125;
    }
    if (getppid() != parent) {
        return 125;
    }
#endif

    int signals[] = {SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGTSTP, SIGCONT};
    for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); index++) {
        if (install_handler(signals[index]) != 0) {
            perror("quill-code process supervisor sigaction");
            return 125;
        }
    }

    pid_t child = fork();
    if (child < 0) {
        perror("quill-code process supervisor fork");
        return 125;
    }
    if (child == 0) {
        restore_default_handlers();
        if (setpgid(0, 0) != 0) {
            perror("quill-code process supervisor setpgid");
            _exit(125);
        }
        execv(argv[1], &argv[1]);
        int exec_error = errno;
        perror("quill-code process supervisor exec");
        _exit(exec_error == ENOENT ? 127 : 126);
    }

    if (setpgid(child, child) != 0 && errno != EACCES && errno != ESRCH) {
        perror("quill-code process supervisor setpgid");
        (void)kill(child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return 125;
    }

#if defined(__APPLE__)
    return monitor_with_kqueue(parent, child);
#else
    return monitor_with_polling(parent, child);
#endif
}
