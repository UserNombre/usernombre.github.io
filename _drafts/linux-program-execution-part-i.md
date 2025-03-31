---
title: "Linux Program Execution, Part I: A Tale of Two Processes"
layout: post
category: articles
tags: [linux, glibc, internals]
---

{%- assign yaml = site.data["linux-program-execution"] -%}

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

# The program

Suppose the following program:
```c
#include <stdio.h>

int
main(void)
{
    puts("Hello World");
}
```

A user would then compile and execute the program above like so:
```console
$ gcc hello.c -o hello
$ ./hello
Hello world
```

```console
$ file hello
hello: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=f6d30f74c7bd8a4f5cac7772db7dbd1d554e6d35, for GNU/Linux 3.2.0, not stripped
```

# The shell

- Shells are the programmer's primary gateway into the operating system.
- I feel it is the appropriate place to begin to describe, used Linux familiar to anyone that's
- bash will be used, as it is commonplace in most modern Linux distributions.

- Linux 6.1 (SLTS) version will be used
- Bash 5.2 on later sections.  as well as glibc 2.40 will be used

At some point somebody types the following into the shell:
```console
$ ./hello
```

Once we hit the enter button on the shell, how is our `main` function reached? This, by no means
an easy question, is what we'll be trying answer throught the series. For now, we'll start by seeing
what is it that bash does with our input[^bash].

{{ "bash_command" | generate_codepath: yaml, 4 }}

# fork()

The call to `fork` but to glibc.

```console
$ readelf -s /usr/bin/bash | grep fork@
   217: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND fork@GLIBC_2.2.5 (2)
```


- Real work done by [wrappers](https://sourceware.org/glibc/wiki/SyscallWrappers), which when
expanded by the [C pre-processor](https://en.wikipedia.org/wiki/C_preprocessor) result in a
simple syscall instruction.
- `INLINE_SYSCALL_CALL` etc

- User mode to kernel mode transition[^linux-syscalls].

- Process creation takes place in `clone` ([UtLK 3.4](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s04.html))
    - Lots of error checking
    - Process selectively cloned via `copy_*` functions according to [`clone_flags`](https://elixir.bootlin.com/linux/v6.1/source/include/uapi/linux/sched.h#L8)
    - The actual execution setup work is done in [`copy_thread`](test).
    - `inactive_task_frame` together with `fork_frame`

{{ "fork" | generate_codepath: yaml, 4 }}

At this point two nearly identical processes exist, but their future couldn't be more different.

## Context switch

- as documented in the docs for the `__schedule` function, there are various means of driving the
scheduler[^linux-scheduling]. For simplicity's sake we will assume `TIF_NEED_RESCHED` is used.

{{ "syscall_schedule" | generate_codepath: yaml, 4 }}

- first execution right after a context switch[^linux-context-switch] ([UtLK 3.3](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/ch03s03.html))
    - hardware context c execution context 
- fork returns 0

- real work done by `context_switch`
- `__switch_to_asm` is one of those key points that I previously mentioned

{{ "task_switch" | generate_codepath: yaml, 4 }}

## Child return

- return to user code in `ret_from_fork`

{{ "child_fork" | generate_codepath: yaml, 4 }}

## Parent return

- fork returns child pid

{{ "parent_fork" | generate_codepath: yaml, 4 }}

---

[^linux-processess]:
    Understanding the Linux Kernel (pages Chapter A)
    https://www.cs.utexas.edu/~rossbach/cs380p/papers/ulk3.pdf

[^bash]:
    Make no mistake, bash is complex enough that many pages could be written about it. Here we are
    only trying to scratch the surface in order to see how it interacts with the operating system.
    Readers interested on an overivew of its internals should check out the chapter dedicated to
    bash in [The Architecture of Open Source Applications](https://aosabook.org/en/v1/bash.html),
    which is written by Chet Ramey, the main developer of bash.

    The [Wikipedia entry](https://en.wikipedia.org/wiki/Bash_(Unix_shell)#History) for bash
    also provides a timeline detailing the history of bash and shells in general.

[^linux-syscalls]:
    Further reading:
    - {{ "https://lwn.net/Articles/604287/" | generate_resource: "Anatomy of a system call" }}

[^linux-clone]:

[^linux-namespaces]:
    PID namespaces introduced in the 2.6.24 kernel ([LWN](https://lwn.net/Articles/259217/))
    Further reading:
    - {{ "https://lwn.net/Articles/531114/" | generate_resource: "Namespaces in operation, part 1: namespaces overview" }}
    - {{ "https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html" | generate_resource: "Digging into Linux namespaces - part 1" }}

[^linux-scheduling]:
    this is described in the [function's documentation](https://elixir.bootlin.com/linux/v6.1/source/kernel/sched/core.c#L6364)

    Further reading:
    - {{ "https://wiki.osdev.org/Kernel_Multitasking" | generate_resource: "Kernel Multitasking" }}
    - {{ "https://wiki.osdev.org/Context_Switching" | generate_resource: "Context Switching" }}
    - {{ "https://www.maizure.org/projects/evolution_x86_context_switch_linux/" | generate_resource: "Evolution of the x86 context switch in Linux" }}
    - {{ "https://linux-kernel-labs.github.io/refs/heads/master/lectures/processes.html" | generate_resource: "Processes" }}
    - {{ "http://lastweek.io/notes/linux/fork/" | generate_resource: "Misc on Linux fork, switch_to, and scheduling" }}

[^linux-context-switch]:
    The actual switching context is variously documented ([1](http://lastweek.io/notes/linux/fork/),[2](https://prathamsahu52.github.io/post/linux_scheduler/))

[^intel-speculation]:
    [patch series](https://lwn.net/Articles/743019/)
