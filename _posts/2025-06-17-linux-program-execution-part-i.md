---
title: "Linux Program Execution, Part I: From the Shell to the Kernel"
layout: post
category: articles
tags: [linux, glibc, bash, internals]
---

{{ site.data["linux-program-execution"] | configure_sourcecode_data }}

> [!] This article is still under construction

Recently, I've been looking at how Linux systems handle program execution. The Linux ecosystem is
great for people curious about implementation details, as most of it is open source. Yet having
access to source code does not instantly grant one knowledge of its workings, especially when
multiple complex pieces of software are involved.

While reading through the code, I've frequently been puzzled at how some things work internally or
why they are implemented the way they are. Thankfully, the Internet is full of knowledgeable people
who do a great job of explaining many of these. However, I haven't been able to find any resources
that attempt to thread all of it into one cohesive narrative, kind of like a walkthrough for code.

With this in mind, I've set out to (hopefully) create a series of articles that will deal with the
execution of a program, starting with the shell invoking it up until the execution of its first line
of code. In this article, we'll only explore the creation of a new process[^article-process], and I
intend for later ones to deal with the execution of a new program and dynamic loading, among other
things. Additionally, for some tangential topics that are not covered here, I'll link to useful
resources I've come across, which should provide a starting point for deeper exploration.

This article is written with `x86-64` systems in mind, as it is what I am most familiar with. Wherever
code is referenced, links to the source are provided to improve browsability[^article-code].

## Introduction

Programs can be executed through various means, but I feel the shell is the appropriate place to
start exploring the topic, as it's probably the simplest out of all of them and most Linux users
will already be familiar with a bunch of the concepts involved. For the sake of convenience
[`bash`](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) will be used, since it is commonplace in
modern Linux distributions.

Our inquiry starts with a command prompt, a command, and an output:
```console?prompt=$
$ cowsay Hello world
 _____________
< Hello world >
 -------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
```

From our perspective, executing a program through the shell is rather simple. We input the program
name followed by some arguments into the command line, press enter, and the shell magically invokes
the program while printing its output back into the terminal. If we are a bit curious, we could
ask the following question: *Once we hit the enter key, what does bash do to execute the program?*

Unlike Windows, which relies on a single call to one of the [`CreateProcess*`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa)
functions to create a new process running, UNIX-like operating systems instead split the process
into two separate functions[^unix-history]: [`fork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fork.html)
to create a clone of the current process and [`exec`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html)
to load the new program. Once that is done, the shell uses [`waitpid`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/wait.html)
to block itself until the new process is done executing.

This simple outline of program execution is something that most people who have studied computer
science or had a look at [The Linux Programming Interface](https://man7.org/tlpi/download/TLPI-24-Process_Creation.pdf)
are familiar with. If we want to go deeper, however, we might come up with a more precise question:
*Once we hit the enter key, how does a computer end up executing instructions from the program?*

This question is way more complex, as we are no longer asking about what takes place from bash's
point of view but from that of the whole system. This, minus some details[^article-io], is what
we'll be trying answer throughout the series.

## Entrypoint

For now, we'll start by seeing what is it that bash does with our input and how it decides to act
based on it. The [REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop) (Read
Eval Print Loop) is the underlying idea that drives both [shells](https://en.wikipedia.org/wiki/Shell_(computing)#Command-line_shells)
and [interpreters](https://en.wikipedia.org/wiki/Interpreter_(computing)). Generally, an environment
that implements it will run a continuous loop that reads and parses user input, attempts to evaluate
it according to a set of rules, and then returns its output (or an error if it should arise) to the
user by printing it.

In our specific case, after bash initializes itself, it enters `reader_loop`, which implements the
main loop of the program. From within, it first carries out the **Read** part of the loop, by
waiting for our input and processing it at `read_command`, which is followed by `execute_command`,
where **Eval** and **Print** take place simultaneously[^bash].

{{ "bash_repl" | generate_codepath }}

Thankfully, parsing is, for the most part, a problem that has been long solved thanks to
[parser generators](https://en.wikipedia.org/wiki/Compiler-compiler), which make writing and reading
parsing code easier. [Bison](https://en.wikipedia.org/wiki/GNU_Bison) is used by bash to generate a
[LALR parser](https://en.wikipedia.org/wiki/LALR_parser) by defining its grammar in
[Yacc](https://en.wikipedia.org/wiki/Yacc) syntax (a mix of C code and notation similar to
[Backus–Naur form](https://en.wikipedia.org/wiki/Backus%E2%80%93Naur_form)). The grammar itself
resides in {{ "" | generate_file_link: "bash", "parse.y" }}, and when fed as input to Bison it
generates the code in {{ "" | generate_file_link: "bash", "y.tab.c" }} and
{{ "" | generate_file_link: "bash", "y.tab.h" }}.

Both `read_command` and `parse_command` are thin wrappers around `yyparse`, which is the main
parsing function. If we executed the example command from the introduction, or any executable for
that matter, we would reach `make_simple_command`, and since we didn't do any redirections, it would
simply call `make_bare_simple_command` and assign the corresponding {{ "command_type" | generate_definition_link }}
to it.

{{ "bash_read" | generate_codepath }}

After the command has been parsed, `execute_command` calls `execute_command_internal`, which
contains the logic that decides how to evaluate it. After a few hundred lines filled with
conditionally compiled code and if statements which I don't fully understand, we reach a switch
based on the `command_type`, and if we follow the `cm_simple` case, we eventually arrive at
`execute_simple_command`. This function takes care of executing all trivial commands, including
builtins and functions, but since our command is neither of them, it is assumed that it will be
found on disk and `execute_disk_command` is called.

Here is where the actual works gets done: `search_for_command` looks for the file in all directories
within the `$PATH` environment variable, and if it finds it, `make_child` is called, which finally
creates a new process by invoking the by now familiar `fork`. It also takes care of setting up
signals and job control information for the new process, but we can ignore it.

{{ "bash_execute" | generate_codepath }}

We found what we were looking for, but now we are left with yet another question: where exactly does
this `fork` call lead us to?

## A fork in the road

### User space

In theory, the `fork` symbol could be pointing anywhere, maybe even to a custom definition within
bash. In practice, however, we know that it must be defined within some system library, most likely
within the [C standard library](https://en.wikipedia.org/wiki/C_standard_library). For most modern
Linux distributions this is going to be [glibc](https://en.wikipedia.org/wiki/Glibc) (GNU C Library),
but there are many other implementations, such as [musl](https://en.wikipedia.org/wiki/Musl) or
[uclibc](https://en.wikipedia.org/wiki/UClibc).

We can check this by ourselves quite easily. First of all, bash, like most executables, is linked
dynamically, which means that it makes use of shared libraries whose symbols won't be available
until run time. We can use [`ldd`](https://www.man7.org/linux/man-pages/man1/ldd.1.html) to list
the libraries (technically shared objects) that are required by the executable.

```console?prompt=$&output=highlighted
$ file $(which bash)
/usr/bin/bash: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), <!dynamically linked!>, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=2de3add7685100c7a623a67e3dd128340642a02c, for GNU/Linux 3.2.0, stripped
$ ldd $(which bash)
        linux-vdso.so.1 (0x00007ffe7e5f7000)
        libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007b1fa46b9000)
        <!libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6!> (0x00007b1fa44c3000)
        /lib64/ld-linux-x86-64.so.2 (0x00007b1fa4847000)
```

In the above output we can see that `libc.so.6` is resolved to `/lib/x86_64-linux-gnu/libc.so.6`,
confirming that our system is using `glibc`. Using [`readelf`](https://www.man7.org/linux/man-pages/man1/readelf.1.html)
we can look for `fork` in the symbol table and see that the executable declares an undefined
reference to it, while the library defines it (symbols displayed by `readelf` are actually followed
by `@`, but that is simply versioning information[^elf-versioning]).

```console?prompt=$&output=highlighted
$ readelf -s -W $(which bash) | grep fork@
<!   217: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND fork@GLIBC_2.2.5 (2)!>
$ readelf -s -W /lib/x86_64-linux-gnu/libc.so.6 | grep fork@
   <...>
   957: 00000000000e16d0  1188 FUNC    GLOBAL DEFAULT   16 __libc_fork@@GLIBC_PRIVATE
  <!1117: 00000000000e16d0  1188 FUNC    WEAK   DEFAULT   16 fork@@GLIBC_2.2.5!>
  1514: 00000000000e16d0  1188 FUNC    GLOBAL DEFAULT   16 __fork@@GLIBC_2.2.5
   <...>
```

With this, we now know where we need to look in order to keep tracing our code. There's still the
question of how execution flows from our executable into the library, but we'll leave that for some
other time. For now, it will suffice to know that the executable works together with the dynamic
linker in order to resolve undefined symbols at run time.

This `fork` right here is not a [system call](https://www.man7.org/linux/man-pages/man2/syscalls.2.html)
but merely a wrapper around one. In order to provide an interface that is both unified across
architectures and convenient (as opposed to the [syscall](https://www.man7.org/linux/man-pages/man2/syscall.2.html)
interface), there is a need to define a wrappers for every system call[^glibc-syscalls]. There are a
few [ways](https://sourceware.org/glibc/wiki/SyscallWrappers) of defining them according to their
requirements. Very simple system calls use an {{ "assembly template" | generate_file_link: "glibc", "sysdeps/unix/syscall-template.S" }}
to generate their code, while more complex ones get their own C file.

If we look for a function definition of `fork`, we won't really find anything. Instead, what we do
find, is an [alias](https://gcc.gnu.org/onlinedocs/gcc/Common-Variable-Attributes.html#index-alias-variable-attribute)
to `__libc_fork`. There some other weird stuff done {{ "below the definition" | generate_file_link: "glibc", "posix/fork.c", 140 }}, but it's not that relevant
to our discussion[^glibc-symbols]. The first thing it does is call `__run_prefork_handlers`, which
runs all handlers registered with [`pthread_atfork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_atfork.html)
that should run before forking. After that, it calls the `nptl` ([Native POSIX Thread Library](https://en.wikipedia.org/wiki/Native_POSIX_Thread_Library))
implementation of `_Fork`.

From there, `arch_fork` is called, which, despite its name, is only implemented once for all Linux
architectures. Then, one of the possible `clone`[^glibc-clone] {{ "variants" | generate_file_link: "glibc", "sysdeps/unix/sysv/linux/kernel-features.h", 129 }}
is invoked with `INLINE_SYSCALL_CALL` according to the particular requirements of the architecture.
For `x86-64` systems only `__ASSUME_CLONE_DEFAULT` is defined, so the last one will be executed.

After the `INLINE_SYSCALL_CALL` macro is fully expanded, we arrive at `internal_syscall5`, which
contains the [extended assembly](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html) required to
perform a system call with 5 arguments. In this final piece of code, the syscall number and
arguments are moved to the appropriate registers according to the {{ "x86-64 syscall convention" | generate_file_link: "glibc", "sysdeps/unix/sysv/linux/x86_64/sysdep.h", 158 }},
and only then calls the `syscall` instruction, passing control to the kernel.

{{ "glibc_fork" | generate_codepath }}

### Kernel space[^linux-utlk]

At this point `syscall` invokes the handler found in the `IA32_LSTAR` model-specific register, which
Linux configures to be `entry_SYSCALL_64`. There are many resources that already do a great job at
explaining the internals of system calls in `x86`[^linux-syscalls], so I'll leave out details and
simply outline relevant functions.

{{ "linux_syscall" | generate_codepath }}

Our journey continues in the `sys_clone` kernel function, which simply shoves arguments into a
structure and passes it to `kernel_clone` (the common backend to most process/thread creation
functions). Within it, `copy_process` handles the meat of the matter (see [UtLK 3.4](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s04.html)
for a detailed breakdown).

Right at the start there's a bunch of error checking to ensure that [`clone_flags`](https://elixir.bootlin.com/linux/v6.1/source/include/uapi/linux/sched.h#L8)
are consistent with each other. After that `dup_task_struct` creates a new process descriptor
([UtLK 3.2](https://learning.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s02.html)),
copies data from its parent into it, allocates space for its kernel stack, and does some other minor
adjustments to the descriptor. After that, `sched_fork` initializes scheduler information for the
process and marks it as new, so that it won't be run while it's being set up.

With the process descriptor ready, all of the major kernel structures that make up a process need to
be configured. These are either cloned or shared by `copy_*` functions, according to the flags we
mentioned previously (`arch_fork` only specifies
`CLONE_CHILD_SETTID | CLONE_CHILD_CLEARTID | SIGCHLD`, so most will be
duplicated). Out of all of these functions `copy_thread` is special, as it is the one in charge of
setting up the execution context.

The way Linux does this is by carefully crafting a stack which, when activated, will perform the
steps expected of a new process returning from fork. The {{ "fork_frame" | generate_definition_link }}
is the structure used to encode this information. It is composed of an {{ "inactive_task_frame" | generate_definition_link }},
which stores kernel state for inactive processes (like a usual [stack frame](https://en.wikipedia.org/wiki/Call_stack#Structure)
would), together with {{ "pt_regs" | generate_definition_link }}, which stores user state right
after entering kernel mode (this is done at the start of `entry_SYSCALL_64`). A stack diagram would
be quite useful to visualize what `copy_thread` does to the new process, but for now this will
hopefully do:

1. Fetch the stack address for `pt_regs` and deduce `fork_frame` and `inactive_task_frame` from it.
2. Initialize `inactive_task_frame` by setting the frame pointer to the encoded version of `pt_regs`
and the return address to `ret_from_fork_asm`.
3. Make the stack pointer point to `fork_frame`, making it the active stack frame.
4. Copy user registers over from the parent process and set `ax` to `0`, as that's what `fork` is
expected to return on the child.

{{ "linux_clone" | generate_codepath }}

If everything has gone well, we now have a new process ready to be run. Back in `kernel_clone` it's
marked as such by `wake_up_new_task`, and its identifier is returned so that it can be passed back
to user space. The process will eventually be picked up by the scheduler and start execution,
but for now we'll see how the parent goes back to user mode.

## Back to user space

### Parent return

Right before returning, `do_syscall_64` performs some checks to decide whether it should use
`sysret` or `iret` to reenter user mode, and since all succeed `sysret` is used. Back in
`entry_SYSCALL_64` the appropriate branch is taken, where setup work done at the start is reverted
and finally `sysretq` is executed, effectively handing execution back to user code right after the
initial `syscall` instruction (for details see [^linux-syscalls]).

{{ "kernel_parent_return" | generate_codepath }}

Before returning to the shell, `__libc_fork` calls `__run_postfork_handlers`, the counterpart to
`__run_prefork_handlers`, indicating to run only those intended for the parent. After returning,
`make_child` restores signals, updates job control information, and stores the pid for the new
process. Finally, after returning from `execute_simple_command`, `wait_for` blocks the shell until
the newly created process terminates[^linux-signals].

{{ "user_parent_return" | generate_codepath }}

As we can see, once the parent is done creating its child, it does little more than wait until it
dies (a fairly weird parenting paradigm in my opinion). With that out of the way, we get into the
interesting part: how does the kernel go from executing one process to another?

### Scheduling

The [scheduler](https://en.wikipedia.org/wiki/Scheduling_(computing)) is the component of an
operating system that decides when and until when a process should run. This task is both complex
and open-ended, which is the reason why historically many algorithms have been developed for Linux,
and even today different {{ "scheduling policies" | generate_file_link: "linux", "include/uapi/linux/sched.h", 112 }}
may be desirable depending on the workload of the system. Scheduling algorithms are somewhat besides
the point, but this makes a great opportunity to peer into some fundamental scheduling principles
and their implementation in Linux[^linux-scheduling].

As {{ "documented" | generate_file_link: "linux", "kernel/sched/core.c", 6510 }} in the `__schedule`
function, there are various means of driving the scheduler, but these can roughly be split into two
groups: those that result from a process yielding execution, and those that don't. In the following
sections we'll look into one example from each of them to get a feel for how the scheduler operates.

#### Yielding

One possible scenario involving a process relinquishing execution would be the `waitpid` call we saw
the parent do after it was done forking. Without going into too much detail, we can see that
`__waitpid` is a simple wrapper around `__wait4`. We enter the kernel through `sys_wait4`, and
eventually arrive at `do_wait`. There we initialize a wait queue entry and add it to the child exit
queue, after which we enter a loop that sets the task state to `TASK_INTERRUPTIBLE`, calls
`__do_wait` to check if we can stop waiting, and if we can't (`-ERESTARTSYS` returned), then
`schedule` is called to yield execution.

{{ "waitpid_schedule" | generate_codepath }}

#### Non-yielding

All non-yielding (or preemptive) scenarios involve the {{ "TIF_NEED_RESCHED" | generate_definition_link }}
flag being set, mainly after a process' [time slice](https://en.wikipedia.org/wiki/Preemption_(computing)#Time_slice)
runs out. The exact mechanism for this will vary from system to system, but it will always be a
timer interrupt of some kind, such as a local [APIC](https://wiki.osdev.org/APIC_timer), which is
registered in the clock event framework by {{ "setup_APIC_timer" | generate_definition_link }}
[^linux-timers].

Once the APIC fires an interrupt request, `sysvec_apic_timer_interrupt` is invoked to handle it,
and `local_apic_timer_interrupt` dispatches the event to appropriate handler, which in our case will
be `tick_handle_periodic`. Skip some functions ahead and we reach `sched_tick`, the function in
charge of updating scheduler information. Among other things, it invokes the tick function for the
active scheduler class, which for most desktop systems will be `task_tick_fair`. Finally, we reach
`update_curr`, which updates the task's runtime statistics, and if it has consumed its time slice,
reschedules it by calling `resched_curr`, which ends up setting the `TIF_NEED_RESCHED` flag.

{{ "apic_reschedule" | generate_codepath }}

After all this, however, `schedule` has not yet been called. Instead, it will be called on the next
possible occassion, which usually means on returns to user space. If we take the syscall code that
we saw above, we will see that after `do_syscall_64` is finished with its work, it calls
`syscall_exit_to_user_mode`. A few functions in, we reach `exit_to_user_mode_loop`, which performs
som final tasks before leaving kernel space, including a call to `schedule` when `TIF_NEED_RESCHED`
is set.

{{ "syscall_schedule" | generate_codepath }}

#### Context switch

Now that the decision to schedule a new process has been made, there are three main tasks left to
do: decide which process will be executed, save the current execution context to the old process,
and then load it from the new one. The first one depends on the scheduler class of the process, but
it isn't that relevant, as we'll assume that our child process is picked. The second and third are
typically bundled together into what's known as a [context switch](https://wiki.osdev.org/Context_Switching)[^linux-context-switch],
and it consists mostly of architecture specific code.

After calling `schedule` we get to `__schedule_loop`, which calls `__schedule` in a loop while the
process requires rescheduling. It is `__schedule` that handles the three points mentioned above by
calling `pick_next_task` and `context_switch`. The implementation of `pick_next_task` has grown
quite complex since the introduction of [core scheduling](https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/core-scheduling.html),
but if we assume the simplest case, only `__pick_next_task` is called, which then dispatches it to
the `pick_next_task_fair` function.

{{ "linux_schedule" | generate_codepath }}

The first thing `context_switch` does is call `prepare_task_switch`, which takes care of updating
scheduling statistics and other varied tasks. This is follwed by `switch_mm_irqs_off`, tasked with
swapping the active address space to that of our new process, as well as some other memory and
synchronization shenanigans. Some lines ahead we reach a turning point in execution: `switch_to`.

Alright, technically `switch_to` is a simple wrapper around `__switch_to_asm`, but the latter **is**
where the process switch actually happens. Understanding how this function works is essential in
order to make sense of the preparation that was made earlier within `copy_thread` and vice versa.
Here is how the switch takes place:

1. Push callee-saved registers (`%rbp`, `%rbx` and `%r12` through `%r16`) to the stack in order to
preserve their values, as specified by the [System V ABI for x86-64](https://wiki.osdev.org/System_V_ABI#x86-64).
Adding this to the usual stack frame, we get an {{ "inactive_task_frame" | generate_definition_link }}
at the top of the stack.
2. Save the value of the stack pointer (`%rsp`) within the previous task (`%rdi`)[^linux-asm-offsets].
This completes the saving of the execution context, allowing for a later restore.
3. Load the value of the stack pointer from the next task (`%rsi`). Conceptually, this completes the
switch, as instructions past this point will reference the stack of the new task, and therefore use
its execution context.
4. Pop callee-saved register from the stack, effectively restoring the values they had the last time
the task was executed (or those set in `copy_thread` for a new task). What is left at the top of the
stack is a bare stack frame.
5. Jump to `__switch_to` in order to finish up some details.

It may appear strange at first that the instruction pointer (`%rip`) isn't saved together with the
other registers, but there's really no need, since next time the saved process gets switched it will
necessarily continue execution on step 4. From a process' point of view, `__switch_to_asm` is split
into two parts: the first one (1-3), which runs when it process hands off execution, and the second
one (4-5), which runs when it regains execution.

{{ "linux_context_switch" | generate_codepath }}

After jumping into `__switch_to` some final, mostly x86 specific, adjustments are made: [segments](https://en.wikipedia.org/wiki/X86_memory_segmentation#Later_developments)
are saved an loaded, [TLS](https://en.wikipedia.org/wiki/Thread-local_storage) pages are set up and
some [per-cpu](https://0xax.gitbooks.io/linux-insides/content/Concepts/linux-cpu-1.html) variables
are updated, along with some less interesting ones. What interests us however, is the inconspicuous
`return` at the end of the function. An existing process returning from `__switch_to` would wind up
back in `context_switch`, then `__schedule`, and eventually continue whatever it was doing before it
was switched. On the other hand, our process can't continue where it left off, since it never
executed in the first place. Instead, `copy_thread` initialized this first stack frame so that a
newly created process returns into `ret_from_fork_asm`.

### Child return

Unlike normal processes, which typically enter the kernel through system calls or interrupts, new
processes have never been in user space, so `ret_from_fork_asm` is in charge of getting them there
for the first time. It first calls `ret_from_fork`, which among other functions ends up calling
`finish_task_switch` (paired with the previous `prepare_task_switch`), which cleans up what's left
of the task switch (mainly memory and timing details) and `syscall_exit_to_user_mode` to handle
pending work before entering user mode. After that, `swapgs_restore_regs_and_return_to_usermode`,
which has a very self-descriptive name, restores user register from `pt_regs`, executes [`swapgs`](https://wiki.osdev.org/SWAPGS),
and finally enters user mode via `iretq`.

{{ "kernel_child_return" | generate_codepath }}

Back in user space everything is almost the same, except for a little twist: `fork` now returns 0,
indicating a child process. This time, before returning from `execute_disk_command`, `shell_execve`
is entered. From there, `execve` is called, and at this point our new process will become an
entirely different one.

{{ "user_child_return" | generate_codepath }}

---

[^article-process]:
    Throughout the article I will use the words "process" and "task" more or less indistinctly to
    refer to both the schedulable unit as well as the `task_struct` that represents it.

[^article-code]:
    Linux and glibc links point to the [Elixir](https://github.com/bootlin/elixir) cross-referencer
    by Bootlin, while bash links point to a fork on GitHub.

    For bash (5.2) and glibc (2.41) the latest releases available at the time of writing are used,
    while for Linux (6.12) the most recent SLTS version is used.

[^unix-history]:
    Among other interesting historical facts, Dennis Ritchie's paper [The Evolution of the Unix Time-sharing System](https://archive.org/details/evolution-of-unix-tss)
    explains how `fork-exec` pairing more or less naturally arose during the development of UNIX.

[^article-io]:
    We won't be going over any of the I/O details, as that topic is complex enough that it would
    require a series of articles of their own.

[^bash]:
    Here we'll only explore how bash interacts with the operating system, but readers interested on
    an overivew of its internals should definetely check out the chapter dedicated to bash in
    [The Architecture of Open Source Applications](https://aosabook.org/en/v1/bash.html), which is
    written by the main developer of bash, Chet Ramey.

[^elf-versioning]:
    Symbol versioning gives authors of shared objects the ability to label symbols with a given
    version number. As far as I know, this is mostly used to detect binary incompatibilities and
    prevent run-time errors when versions are mismatched.

    Further reading:
    - {{ "https://maskray.me/blog/2020-11-26-all-about-symbol-versioning" | generate_resource: "All about symbol versioning" }}
    - {{ "https://akkadia.org/drepper/symbol-versioning" | generate_resource: "ELF Symbol Versioning" }}

[^glibc-syscalls]:
    In the [past](https://lwn.net/Articles/655028/) many system calls didn't have a corresponding
    wrapper in `glibc`, so [syscall](https://www.man7.org/linux/man-pages/man2/syscall.2.html) had
    to be used instead. I'm not sure how much has changed since, but things are likely better now.

[^glibc-symbols]:
    In addition to `fork`, we see that `__fork` is also defined as an alias for `__libc_fork` using
    {{ "weak_alias" | generate_definition_link }}. However, `__fork` is later passed to
    {{ "libc_hidden_def" | generate_definition_link }}, which defines an [internal symbol](https://stackoverflow.com/a/21422495)
    to ensure that calls within `glibc` are routed to it, preventing symbol resolution overhead.
    This is more or less {{ "documented" | generate_file_link: "glibc", "libc-symbols.h", 365 }}
    in the header where these macros are defined. Still, it's not entirely clear to me why it has
    the need to alias `__fork`, instead of simply hiding `__libc_fork`, since that's what's done for
    other syscalls {{ "dup2" | generate_file_link: "glibc", "sysdeps/unix/sysv/linux/dup2.c", 39 }}.

    Further reading:
    - {{ "https://gcc.gnu.org/onlinedocs/gcc/Asm-Labels.html" | generate_resource: "Controlling Names Used in Assembler Code" }}
    - {{ "https://gcc.gnu.org/wiki/Visibility" | generate_resource: "Visibility" }}
    - {{ "https://maskray.me/blog/2021-06-20-symbol-processing" | generate_resource: "Symbol processing" }}
    - {{ "https://maskray.me/blog/2021-04-25-weak-symbol" | generate_resource: "Weak symbol" }}

[^glibc-clone]:
    It may appear strange for `fork` wrapper to end up invoking the `clone` system call, but this
    has been done since at least version [2.3.2](https://elixir.bootlin.com/glibc/glibc-2.3.2/source/nptl/sysdeps/unix/sysv/linux/i386/fork.c#L27)
    in `i386`, probably because in the kernel `sys_fork` also ends up delegating to `sys_clone`.

[^linux-syscalls]:
    See:
    - {{ "https://0xax.gitbooks.io/linux-insides/content/SysCall/linux-syscall-2.html" | generate_resource: "How does the Linux kernel handle a system call" }}
    - {{ "https://juliensobczak.com/inspect/2021/08/10/linux-system-calls-under-the-hood/#kernel-mode-linux" | generate_resource: "Linux System Calls Under The Hood" }}
    - {{ "https://blog.slowerzs.net/posts/linux-kernel-syscalls/" | generate_resource: "Linux Kernel - Syscalls" }}
    - {{ "https://lwn.net/Articles/604287/" | generate_resource: "Anatomy of a system call, part 1" }}
    - {{ "https://lwn.net/Articles/604515/" | generate_resource: "Anatomy of a system call, part 2" }}

[^linux-utlk]:
    Everything that follows is my best attempt at explaining how the kernel creates a new process
    and starts its execution. There will probably be some gaps in it, so I would recommend the
    reader to grab a copy of [Understanding the Linux Kernel](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/)
    to expand on some of the topics.

    It is the most comprehensive book on the subject, and although a bit outdated (the 3rd edition
    was written for version 2.6), it's still very useful to understand the big picture, which has
    not changed that much over the years.

[^linux-vmap-stack]:
    The actual definition of `alloc_thread_stack_node` depends on the {{ "VMAP_STACK" | generate_definition_link }}
    configuration option, which on `x86-64` ends up enabled by default.

    Further reading:
    - {{ "https://lwn.net/Articles/692208/" | generate_resource: "Virtually mapped kernel stacks" }}
    - {{ "https://www.kernel.org/doc/html/latest/mm/vmalloced-kernel-stacks.html" | generate_resource: "Virtually Mapped Kernel Stack Support" }}

[^linux-namespaces]:
    Since the introduction of PID namespaces in version [2.6.24](https://lwn.net/Articles/259217/)
    the value returned is the virtual process identifier.

    Further reading:
    - {{ "https://lwn.net/Articles/531114/" | generate_resource: "Namespaces in operation, part 1: namespaces overview" }}
    - {{ "https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html" | generate_resource: "Digging into Linux namespaces - part 1" }}

[^linux-signals]:
    Of course we can still interact with the shell through signals, but that's a story for some other time.

[^linux-scheduling]:
    A good overview, even if somewhat dated, of Linux's core scheduling principles, algorithms, as
    well as implementation details can be found on [UtLK 7](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch07.html).

    Further reading:
    - {{ "https://lwn.net/Articles/87729/" | generate_resource: "The staircase scheduler" }}
    - {{ "https://lwn.net/Articles/224865/" | generate_resource: "The Rotating Staircase Deadline Scheduler" }}
    - {{ "https://lwn.net/Articles/230574/" | generate_resource: "Schedulers: the plot thickens" }}
    - {{ "https://lwn.net/Articles/922405/" | generate_resource: "The extensible scheduler class" }}
    - {{ "https://lwn.net/Articles/925371/" | generate_resource: "An EEVDF CPU scheduler for Linux" }}

[^linux-timers]:
    The timer subsystem is quite complex, and since different systems can have different timing
    devices and configurations I'm not sure if there is a general case. For this reason, we assume
    that periodic interrupts are handled by the local APIC in each CPU.

    Further reading:
    - {{ "https://wiki.osdev.org/Timer_Interrupt_Sources" | generate_resource: "Timer Interrupt Sources" }}
    - {{ "https://0xax.gitbooks.io/linux-insides/content/Timers/linux-timers-5.html" | generate_resource: "Introduction to the clockevents framework" }}
    - {{ "https://www.linuxfoundation.org/webinars/the-ticking-beast-a-deep-dive-into-timers-timekeeping-tick-and-tickless-kernels" | generate_resource: "The Ticking Beast" }}

[^linux-context-switch]:
    A description of the context switch can be found on [UtLK 3.3](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s03.html),
    but because it was written for version 2.6 and contains i386 specific code, much has changed
    since. Instead, I recommend reading the [Evolution of the x86 context switch in Linux](https://www.maizure.org/projects/evolution_x86_context_switch_linux/),
    which explores the context switch across different kernel versions, including a more recent one
    (4.16).

[^linux-asm-offsets]:
    The previous task is referenced by `%rdi`, and {{ "TASK_threadsp" | generate_definition_link }}
    is a constant containing the offset of the `thread.sp` field within `task_struct`. These
    constants are generated quite early in the {{ "top-level Kbuild" | generate_file_link: "linux", "Kbuild", "26" }}
    and are mostly used in assembly code, which doesn't have access to C structures.
