---
title: "Linux Program Execution in x86-64, Part I: A Tale of Two Processes"
layout: post
category: articles
tags: [linux, glibc, internals]
---

{{ site.data["linux-program-execution-x86-64"] | configure_sourcecode_data }}

- linux kernel daunting software
    - I, like many others, like understanding how software works.
    - I've read pieces here and there, so I have a rough idea of how some things work.
    - One of the essential pieces of an operating system, that of process execution, oftend still
    appears elusive to me due to the large amount of moving pieces in modern Linux systems

- well known topic, much written about it
    - [Understanding the Linux Kernel](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/),
    major resource giving a detailed description regarding implementation of the Linux kernel
        - referenced throughout as UtLK
        - point when changes have occurred if any
    - and so with the purpose a more detailed understanding I've decided to study and write an
    up-to-date.
    - For the purpose of consistency, the latest SLTS version (6.12), will be used.
    - hopes to provide a starting point into deeper exploration of interesting concepts and topics
    by piecing together what useful resources I've come accross

- intends to be the first article in a multipart series
    - this part will deal with the creation of processes
    - thread together

- For quite some time now I've been delaying the writing of this article because I couldn't find the
"perfect" way of structuring sections, laying out code, handling references, and a long etcetera.
"Perfect is the enemy of good" goes the saying, and so I've chosen to publish it as is.
While it is obviously far away from perfect, I hope that it can at least be qualified as good.

# Introduction

- Shells are the programmer's primary gateway into the operating system.
- I feel it is the appropriate place to begin to describe, used Linux familiar to anyone that's
- bash will be used, as it is commonplace in most modern Linux distributions.

At some point somebody types the following into the shell:
```console
$ fortune
Don't you wish you had more energy... or less ambition?
```

Once we hit the enter button on the shell, how is its `main` function reached? This, by no means
an easy question, is what we'll be trying answer throught the series. 

## Versions

- x86-64 system
- Linux 6.1 (SLTS) version will be used
- Bash 5.2 on later sections.  as well as glibc 2.40 will be used

# Execution

## bash

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

{{ "bash_read" | generate_codepath }}

- Once the command is parsed it type {{ "command_type" | generate_definition_link }}.

{{ "bash_execute" | generate_codepath }}

## fork()

- Unlike Windows' [`CreateProcess*`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa)
family of functions, instead it uses [`fork`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fork.html),
UNIX used and which most operating systems derived from it still use.

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

- Process creation takes place in `clone` ([UtLK 3.4](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s04.html))
    - Lots of error checking
    - `copy_*` Process selectively cloned via `copy_*` functions according to [`clone_flags`](https://elixir.bootlin.com/linux/v6.1/source/include/uapi/linux/sched.h#L8)
    - The actual execution setup work is done in `copy_thread`.
    - {{ "inactive_task_frame" | generate_definition_link }} together with
    {{ "fork_frame" | generate_definition_link }}

{{ "fork_kernel" | generate_codepath }}

At this point two nearly identical processes exist, but their future couldn't be more different.

## Parent return

- fork returns child pid

`sysret` or `iret` according to logic found within {{ "do_syscall_64" | generate_definition_link }}.
Since we entered via the `syscall` instruction, it needs to be paired with the corresponding `sysret`.

{{ "parent_return" | generate_codepath }}

{{ "parent_fork" | generate_codepath }}

## Context switch

- as documented in the docs for the `__schedule` function, there are various means of driving the
scheduler[^linux-scheduling].
- For simplicity's sake we'll assume `TIF_NEED_RESCHED` is used.

{{ "syscall_schedule" | generate_codepath }}

- first execution right after a context switch[^linux-context-switch] ([UtLK 3.3](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s03.html))
    - hardware context c execution context 
- real work done by `context_switch`
- `__switch_to_asm` is one of those key points that I previously mentioned

{{ "task_switch" | generate_codepath }}

## Child return

- return to user code in `ret_from_fork`

{{ "child_return" | generate_codepath }}

- fork returns 0

{{ "child_fork" | generate_codepath }}

---

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

[^linux-syscalls]:
    Further reading:
    - {{ "https://lwn.net/Articles/604287/" | generate_resource: "Anatomy of a system call" }}

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
