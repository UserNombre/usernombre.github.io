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

---

[^article-code]:
    Linux and glibc links point to the [Elixir](https://github.com/bootlin/elixir) cross-referencer
    by Bootlin, while bash links point to a fork on GitHub.

    For bash (5.2) and glibc (2.41) the latest releases available at the time of writing are used,
    while for Linux (6.12) the most recent SLTS version is used.
