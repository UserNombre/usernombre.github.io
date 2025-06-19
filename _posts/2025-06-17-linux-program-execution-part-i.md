---
title: "Linux Program Execution, Part I: From the Shell to the Kernel"
layout: post
category: articles
tags: [linux, glibc, bash, internals]
---

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
