---
title: "Linux Program Execution, Part I: A Tale of Two Processes"
layout: post
category: articles
tags: [linux, glibc, internals]
---

{{ site.data["linux-program-execution-x86-64"] | configure_sourcecode_data }}

Anyone who has worked with computers for long has probably wondered how this or that
feature is implemented under the hood. I, like many others, like understanding how a computer works
down to the .

The Linux ecosystem, being open source, is a great .

The fact that code does not instantly grant you
    - open source, yet navigating is hard
    - I've read pieces here and there, so I have a rough idea of how some things work.

While researching the topic of program execution I've come across a lot of material which explores
some aspect of it. However, I haven't been able to find any from , so I've decided to
publish hopefully will double for others as well.

In this article we will only explore the creation of a new process, but I intend to write at least
two other ones, dealing with the execution of a new program and dynamic loading respectively.
    - allow easy navigation of the code by thread together components of the ecosystem and
    highlight key points
    - hopes to provide a starting point into deeper exploration of interesting concepts and topics
    by piecing together what useful resources I've come accross

will be x86-64 system, I am most familiar with.

## Introduction

Programs can be executed through various means, but I feel the shell is the appropriate place to
start exploring the topic, since it's probably the simplest and most Linux users will already be
familiar with some of the concepts involved. For the sake of convenience `bash` will be used, as it
is commonplace in modern Linux distributions.

At some point somebody types the following into the shell:
```console
$ fortune
Don't you wish you had more energy... or less ambition?
```

We might ask the following question:
> Once we hit the enter button, how does bash execute our program?

- [interface](https://man7.org/tlpi/download/TLPI-24-Process_Creation.pdf)

- Unlike Windows' [`CreateProcess*`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa)
family of functions, UNIX-like operating systems instead into two [`fork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fork.html),
and [`exec`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html). This is mostly
due to historial reasons[^unix-history].
- while not wrong, simplification, fine for an introduction.

Unsatisfied with the answer, we might come up with a more precise question:
> Once we hit the enter button, what code does our computer execute until the `main` function of our
executable is reached?

This, by no means an easy question, this (minus I/O details) is what we'll be trying answer
throughout the series.

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
`execute_disk_command` is called. Within it, `search_for_command` looks for the file in all
directories in the `$PATH` environment variable, and if it finds it, `make_child` is called, which
kick-starts the actual execution by invoking the familiar `fork`.

{{ "bash_execute" | generate_codepath }}

## A fork in the road

At this point we could skip ahead and simply say that `fork` only a wrapper that invokes the actual
function from the kernel, but I believe some of these details are worth knowing.

### User space

- We can confirm that `fork` does indeed call into `glibc`.

```console
$ readelf -s $(which bash) | grep fork@
   217: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND fork@GLIBC_2.2.5 (2)
```

- Strong symbol `__libc_fork`, `fork` weak symbol

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

{{ "child_return" | generate_codepath }}

- fork returns 0

{{ "child_fork" | generate_codepath }}

---


[^code-version]:
    - Bash 5.2
    - glibc 2.41
    - linux 6.12
        - For the purpose of consistency, the latest SLTS version (6.12), will be used.

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

[^unix-history]:
    https://stackoverflow.com/questions/8292217/why-fork-works-the-way-it-does
    UNIX used and which most operating systems derived from it still use.

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
