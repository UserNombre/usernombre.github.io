---
title: "Linux Program Execution, Part I: From the Shell to the Kernel"
layout: post
category: articles
tags: [linux, glibc, bash, internals]
---

{{ site.data["linux-program-execution-x86-64"] | configure_sourcecode_data }}

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

This article is written with x86-64 systems in mind, as it is what I am most familiar with. Wherever
code is referenced, links to the source are provided to improve browsability[^article-code].

## Introduction

Programs can be executed through various means, but I feel the shell is the appropriate place to
start exploring the topic, as it's probably the simplest of them and most Linux users will already
be familiar with a bunch of the concepts involved. For the sake of convenience `bash` will be used,
as it is commonplace in modern Linux distributions.

Our inquiry starts with a simple command prompt. At some point a bored programmer decides to execute a
random command:
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

This simple can gives rise to a plethora of questions, but we will limit ourselves to one of them.
- the shell does not have knowledge on the program
- We might ask the following question: How does bash execute our program once we hit the enter
button?
    [multitasking](https://en.wikipedia.org/wiki/Computer_multitasking), might sound obvious, but
    before the advent of operating systems
    [batch processing](https://en.wikipedia.org/wiki/Batch_processing) was the norm and shells in
    the modern sense were not possible

    [resident monitor](https://en.wikipedia.org/wiki/Resident_monitor)
    New process loaded with program, execute
    This is what most people familiar with operating systems 

- What code does the shell execute to create the new process and load the program?
    - Familiar with UNIX knows that Unlike Windows' [`CreateProcess*`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa)
    family of functions, UNIX-like operating systems instead split the process into two system calls
    [`fork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fork.html) and
    [`exec`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html). This is mostly
    due to historial reasons[^unix-history].
    This is something that most people who have studied computer science or that have had a look at
    [The Linux Programming Interface](https://man7.org/tlpi/download/TLPI-24-Process_Creation.pdf)
    know.

- Unsatisfied with the answer, we might come up with a more precise question: Once we hit the enter
button, what code does our computer execute until the `main` function of our executable is reached?
    This last question, which by no means an easy one, is what we'll be trying answer throughout the
    series[].

## Entrypoint

- For now, we'll start by seeing what is it that bash does with our input.
- `bash`, like any other shells, is based around the simple[^bash] concept of a
[REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop) (Read Eval Print Loop).
- In our example, code execution starts on the **Read** phase of the bash loop, waiting for our input
within `read_command`, while **Eval** and **Print** take place simultaneously within `execute_command`.

{{ "bash_repl" | generate_codepath }}

- The function reads our input and parses it in order to figure out the proper way to execute.
{{ "" | generate_file_link: "bash", "parse.y" }} defines a [Yacc](https://en.wikipedia.org/wiki/Yacc)
grammar which is then fed to [Bison](https://en.wikipedia.org/wiki/GNU_Bison) in order to generate
the actual parsing code in {{ "" | generate_file_link: "bash", "y.tab.c" }} and
{{ "" | generate_file_link: "bash", "y.tab.h" }}.
- Once the command is parsed it type {{ "command_type" | generate_definition_link }}.

{{ "bash_read" | generate_codepath }}

After parsing, execution takes place in the aptly named `execute_command` function. Based on the
`cm_simple` type, the `execute_simple_command` function is entered, and since the command is
neither a builtin nor a function it is assumed that it will be found on disk and
`execute_disk_command` is called.

Here is where the actual works gets done: `search_for_command` looks for the file in all directories
found in the `$PATH` environment variable, and if it finds it, `make_child` is called, which
kick-starts the actual execution by invoking the familiar `fork`. But where exactly is `fork`
defined?

{{ "bash_execute" | generate_codepath }}


## A fork in the road

### User space

As many will know, system calls are routed to the kernel by the
[C standard library](https://en.wikipedia.org/wiki/C_standard_library). For most modern Linux
distributions this will be [glibc](https://en.wikipedia.org/wiki/Glibc) (GNU C Library), but there
are many other implementations, such as [musl](https://en.wikipedia.org/wiki/Musl) or
[uclibc](https://en.wikipedia.org/wiki/UClibc).

Using `readelf` we can confirm that in our particular system `fork` does indeed call into `glibc`:
```console
$ readelf -s $(which bash) | grep fork@
   217: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND fork@GLIBC_2.2.5 (2)
```

If we look for the implementation of `fork` we'll eventually that `__libc_fork`.

Below the function definition itself we'll see that `weak_alias` is used to define
a weak alias from `fork` and `__fork` to `__libc_fork`.

We also notice that `__fork` is passed to `libc_hidden_def`, which defines an
[internal symbol](https://stackoverflow.com/a/21422495) to ensure that calls within glibc are
properly resolved, found in GDB stack traces.

checking with [`ldd`](https://www.man7.org/linux/man-pages/man1/ldd.1.html)

```console?prompt=$
$ ldd $(which bash)
        linux-vdso.so.1 (0x00007ffe7e5f7000)
        libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007b1fa46b9000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007b1fa44c3000)
        /lib64/ld-linux-x86-64.so.2 (0x00007b1fa4847000)
```


```console
$ readelf -s -W /lib/x86_64-linux-gnu/libc.so.6 | grep fork@
   (...)
   957: 00000000000e16d0  1188 FUNC    GLOBAL DEFAULT   16 __libc_fork@@GLIBC_PRIVATE
  1117: 00000000000e16d0  1188 FUNC    WEAK   DEFAULT   16 fork@@GLIBC_2.2.5
  1514: 00000000000e16d0  1188 FUNC    GLOBAL DEFAULT   16 __fork@@GLIBC_2.2.5
   (...)
```

- `_Fork` is implemented as part of the implementation for `nptl`
([Native POSIX Thread Library](https://en.wikipedia.org/wiki/Native_POSIX_Thread_Library)).

- After that, `arch_fork` is called, which, despite its name, is only implemented once for all Linux
systems. Once we remove [C preprocessor](https://en.wikipedia.org/wiki/C_preprocessor) conditional
statements, which are required for backwards compatibility, we are left with a single call to
{{ "INLINE_SYSCALL_CALL" | generate_definition_link }}.

- As one might guess from its letter case, `INLINE_SYSCALL_CALL` is not an actual function but a
macro. Real work done by [wrappers](https://sourceware.org/glibc/wiki/SyscallWrappers), which when
expanded result in a simple `syscall` instruction.

`internal_syscall5`, syscall number linux convention
({{ "56" | generate_file_link: "linux", "arch/x86/entry/syscalls/syscall_64.tbl", 68 }}))
passed in `%rax`

- User mode to kernel mode transition[^linux-syscalls].

{{ "" | generate_file_link: "linux", "scripts/syscalltbl.sh" }}
{{ "" | generate_file_link: "linux", "arch/x86/entry/syscalls/Makefile" }}
{{ "" | generate_file_link: "linux", "arch/x86/entry/syscalls/syscall_64.tbl" }}

{{ "fork_user" | generate_codepath }}

### Kernel space

- Process creation takes place in `clone` ([UtLK 3.4](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s04.html))
    - Lots of error checking
    - `copy_*` Process selectively cloned via `copy_*` functions according to [`clone_flags`](https://elixir.bootlin.com/linux/v6.1/source/include/uapi/linux/sched.h#L8)
    - explaining what every functions does is out of the scope of this article, further reading
    - The actual execution setup work is done in `copy_thread`.
    - {{ "inactive_task_frame" | generate_definition_link }} together with
    {{ "fork_frame" | generate_definition_link }}

{{ "fork_kernel" | generate_codepath }}

At this point two nearly identical processes exist, but their future couldn't be more different.

## Back to user space

### Parent return

- fork returns child pid

`sysret` or `iret` according to logic found within {{ "do_syscall_64" | generate_definition_link }}.
Since we entered via the `syscall` instruction, it needs to be paired with the corresponding `sysret`.

{{ "parent_return" | generate_codepath }}

{{ "parent_fork" | generate_codepath }}

### Context switch

- as documented in the docs for the `__schedule` function, there are various means of driving the
scheduler[^linux-scheduling].
- For simplicity's sake we'll assume `TIF_NEED_RESCHED` is used.

{{ "syscall_schedule" | generate_codepath }}

- first execution right after a context switch[^linux-context-switch] ([UtLK 3.3](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s03.html))
    - hardware context c execution context
- real work done by `context_switch`
- `__switch_to_asm` is one of those key points that I previously mentioned
- {{ "TASK_threadsp" | generate_definition_link }} is a constant containing the offset of the
`thread.sp` field within `task_struct`. These constants are generated quite early in the
{{ "top-level Kbuild" | generate_file_link: "linux", "Kbuild", "26" }}.

1. Callee-saved registers (`%rbp`, `%rbx` and `%r12` through `%r16`) are pushed to the stack in
order to preserve their values, as specified by the [System V ABI for x86-64](https://wiki.osdev.org/System_V_ABI#x86-64).
At this point in time, the layout of the top of the stack is exactly
{{ "fork_frame" | generate_definition_link }}.
2. `%rdi` points to the previous task, value of `%rsp` saved into the `thread.sp` field.
3. `%rsi` points to the next task, load `thread.sp` into `%rsp`. After this instruction, the task
switch is conceptually completed, as the stack, which contains a program's execution context is
restored to its previous state. Therefore, instructions past this point are executed as part of the
child process.
4. Callee-saved register are popped from the stack, effectively reversing step 1 and restoring the
values that they had the last time the task was executed.

{{ "task_switch" | generate_codepath }}

### Child return

- return to user code in `ret_from_fork`

https://en.wikipedia.org/wiki/Kernel_page-table_isolation

{{ "child_return" | generate_codepath }}

- fork returns 0

{{ "child_fork" | generate_codepath }}

---

[^article-code]:
    Linux and glibc links point to the [Elixir](https://github.com/bootlin/elixir) cross-referencer
    by Bootlin, while bash links point to a fork on GitHub.

    For bash (5.2) and glibc (2.41) the latest releases available at the time of writing are used,
    while for Linux (6.12) the most recent SLTS version is used.

[^os-history]:
    https://ghostarchive.org/archive/m4fHH
    - https://en.wikipedia.org/wiki/Batch_processing
        - https://en.wikipedia.org/wiki/Resident_monitor
    - https://en.wikipedia.org/wiki/Computer_multitasking#Multiprogramming
        - https://en.wikipedia.org/wiki/Atlas_Supervisor
    - https://en.wikipedia.org/wiki/Time-sharing
        - https://en.wikipedia.org/wiki/Compatible_Time-Sharing_System
        - https://en.wikipedia.org/wiki/Shell_(computing)
        - https://en.wikipedia.org/wiki/Interactive_computing

[^unix-history]:
    https://stackoverflow.com/questions/8292217/why-fork-works-the-way-it-does
    [The Evolution of the Unix Time-sharing System](https://archive.org/details/evolution-of-unix-tss)
    UNIX used and which most operating systems derived from it still use.

[^article-io]
    Except for all of the I/O details, which would require of their own.

[^linux-processess]:
    Understanding the Linux Kernel (pages Chapter A)
    https://www.cs.utexas.edu/~rossbach/cs380p/papers/ulk3.pdf

[^bash]:
    Make no mistake, even if the underlying concept is quite simple, bash is complex enough that
    many pages could be written about it. Here we are only trying to scratch the surface in order to
    see how it interacts with the operating system. Readers interested on an overivew of its
    internals should check out the chapter dedicated to bash in
    [The Architecture of Open Source Applications](https://aosabook.org/en/v1/bash.html), which is
    written by the main developer of bash, Chet Ramey.


[^elf-symbols]:
    https://sourceware.org/glibc/wiki/SyscallWrappers
    https://www.akkadia.org/drepper/dsohowto.pdf
    https://stackoverflow.com/a/21422495
    https://gcc.gnu.org/wiki/Visibility
    https://gcc.gnu.org/onlinedocs/gcc/Asm-Labels.html
    https://maskray.me/blog/2021-06-20-symbol-processing
    https://maskray.me/blog/2021-04-25-weak-symbol
    https://maskray.me/blog/2024-05-26-evolution-of-elf-object-file-format

[^linux-syscalls]:
    Further reading:
    - {{ "https://lwn.net/Articles/604287/" | generate_resource: "Anatomy of a system call, part 1" }}
    - {{ "https://lwn.net/Articles/604287/" | generate_resource: "Anatomy of a system call, part 2" }}
    - {{ "https://0xax.gitbooks.io/linux-insides/content/SysCall/" | generate_resource: "System calls" }}
    - {{ "https://blog.packagecloud.io/the-definitive-guide-to-linux-system-calls/" | generate_resource: "The Definitive Guide to Linux System Calls" }}

[^linux-clone]:

[^posix-spawn]:
    Posix does define [`posix_spawn`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/posix_spawn.html).

[^linux-namespaces]:
    PID namespaces introduced in the 2.6.24 kernel ([LWN](https://lwn.net/Articles/259217/))
    Further reading:
    - {{ "https://lwn.net/Articles/531114/" | generate_resource: "Namespaces in operation, part 1: namespaces overview" }}
    - {{ "https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html" | generate_resource: "Digging into Linux namespaces - part 1" }}

[^linux-scheduling]:
    Means to drive the scheudler are described in the [function's documentation](https://elixir.bootlin.com/linux/v6.1/source/kernel/sched/core.c#L6364).
    Further reading:
    - {{ "https://lwn.net/Articles/87729/" | generate_resource: "The staircase scheduler" }}
    - {{ "https://lwn.net/Articles/224865/" | generate_resource: "The Rotating Staircase Deadline Scheduler" }}
    - {{ "https://lwn.net/Articles/230574/" | generate_resource: "Schedulers: the plot thickens" }}
    - {{ "https://lwn.net/Articles/922405/" | generate_resource: "The extensible scheduler class" }}
    - {{ "https://lwn.net/Articles/925371/" | generate_resource: "An EEVDF CPU scheduler for Linux" }}

[^linux-context-switch]:
    Further reading:
    - {{ "https://wiki.osdev.org/Kernel_Multitasking" | generate_resource: "Kernel Multitasking" }}
    - {{ "https://wiki.osdev.org/Context_Switching" | generate_resource: "Context Switching" }}
    - {{ "https://www.maizure.org/projects/evolution_x86_context_switch_linux/" | generate_resource: "Evolution of the x86 context switch in Linux" }}
    - {{ "https://linux-kernel-labs.github.io/refs/heads/master/lectures/processes.html" | generate_resource: "Processes" }}
    - {{ "http://lastweek.io/notes/linux/fork/" | generate_resource: "Misc on Linux fork, switch_to, and scheduling" }}

[^linux-core-scheduling]:
    The code for `pick_next_task` depends on whether the
    [core scheduling](https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/core-scheduling.html)
    security mechanism is enabled or not via {{ "SCHED_CORE" | generate_definition_link }}. It
    depends on {{ "SCHED_SMT" | generate_definition_link }}, which in x86 is enabled by default for
    `SMP` systems.

    Further reading:
    - {{ "https://lwn.net/Articles/780703/" | generate_resource: "Core scheduling" }}
    - {{ "https://lwn.net/Articles/799454/" | generate_resource: "Many uses for Core scheduling" }}

[^intel-fred]:
    FRED is a recent feature which was [merged in 6.9](https://www.phoronix.com/news/Intel-FRED-Merged-Linux-6.9).
    Further reading:
    - {{ "https://www.intel.com/content/www/us/en/content-details/819481/flexible-return-and-event-delivery-fred-specification.html" | generate_resource: "Flexible Return and Event Delivery (FRED) Specification" }}
    - {{ "https://docs.kernel.org/arch/x86/x86_64/fred.html" | generate_resource: "Flexible Return and Event Delivery (FRED)" }}

[^intel-speculation]:
    This is not a core part of the functionality but a mitigation introduced to combat the
    [Spectre](https://spectreattack.com/) and [Meltdown](https://meltdownattack.com/) attacks on the
    x86 architecture. Change introduced in the [IBRS patch series](https://lkml.org/lkml/2018/1/4/615).
    Oracle has a great article titled [Understanding Spectre v2 Mitigations on x86](https://blogs.oracle.com/linux/post/understanding-spectre-v2-mitigations-on-x86).

    Further reading:
    - {{ "https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/indirect-branch-restricted-speculation.html" | generate_resource: "Indirect Branch Restricted Speculation" }}
    - {{ "https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/spectre.html" | generate_resource: "Spectre Side Channels" }}

[^libc-postfork]:
    [`pthread_atfork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_atfork.html)
