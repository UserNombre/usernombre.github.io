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
of code. In this article, we'll only explore the creation of a new process, and I intend for later
ones to deal with the execution of a new program and dynamic loading, among other things.
Additionally, for some tangential topics that are not covered here, I'll link to useful resources
I've come across, which should provide a starting point for deeper exploration.

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

---

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
