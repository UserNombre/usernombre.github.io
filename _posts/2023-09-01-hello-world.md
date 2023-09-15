---
layout: post
category: articles
tags: web
---

This page aims to be a technical demo for the website as well as a means of documentation.

## Framework

The site is built with [Jekyll](https://jekyllrb.com/), a [static site generator](https://en.wikipedia.org/wiki/Static_site_generator)
written in Ruby. Jekyll takes a [structured directory](https://jekyllrb.com/docs/structure/) as input,
and, after processing, outputs a `_site` directory which can be served by most web servers or
[hosting providers](https://jekyllrb.com/docs/deployment/third-party/).

For the time being it is hosted on [GitHub Pages](https://pages.github.com/), which uses Jekyll by
default, and is deployed through the [default action](https://github.blog/changelog/2021-12-16-github-pages-using-github-actions-for-builds-and-deployments-for-public-repositories/).
At some point it may be worth using a [custom action](https://github.blog/2022-08-10-github-pages-now-uses-actions-by-default/),
which would allow updating dependencies or using plugins not supported by
[default](https://pages.github.com/versions/)[^github-pages-plugins].

## Markup

Site content can be created through [pages](https://jekyllrb.com/docs/pages/) and [posts](https://jekyllrb.com/docs/posts/),
both of which can be written either in HTML or Markdown. Markdown tends to be preferred for simple
content such as posts, as it is more straightforward to write than HTML, even if less powerful.

Markdown is processed by [Kramdown](https://kramdown.gettalong.org) using GitHub's [GFM](https://github.github.com/gfm/)
as the default syntax[^jekyll-markdown]. When writing more complex content, such as math text
requiring special markup like subscripts, [inline HTML](https://kramdown.gettalong.org/syntax.html#html-spans)
can be used for the task. Kramdown also provides other handy features such as [footnotes](https://kramdown.gettalong.org/syntax.html#footnotes)
or [inline attribute lists](https://kramdown.gettalong.org/syntax.html#inline-attribute-lists),
which can set HTML attributes for the given block, for instance to style elements.

<div markdown="1" class="side-by-side">

```md
|                   | 0                                 | 1                 |
|------------------:|:----------------------------------|:------------------|
| → q<sub>0</sub>   | {q<sub>0</sub>, q<sub>1</sub>}    | {q<sub>0</sub>}   |
|   q<sub>1</sub>   | &#8709;                           | {q<sub>1</sub>}   |
|  *q<sub>2</sub>   | &#8709;                           | &#8709;           |
{: .math}
```

|                   | 0                                 | 1                 |
|------------------:|:----------------------------------|:------------------|
| → q<sub>0</sub>   | {q<sub>0</sub>, q<sub>1</sub>}    | {q<sub>0</sub>}   |
|   q<sub>1</sub>   | &#8709;                           | {q<sub>1</sub>}   |
|  *q<sub>2</sub>   | &#8709;                           | &#8709;           |
{: .math}

</div>

Some other constructs which are not possible using Markdown alone, such as the side-by-side
code block and table, are possible thanks to [HTML blocks](https://kramdown.gettalong.org/syntax.html#html-blocks),
which can contain further Markdown:

~~~md
<div markdown="1" class="side-by-side">

```md
|                   | 0                                 | 1                 |
|------------------:|:----------------------------------|:------------------|
| → q<sub>0</sub>   | {q<sub>0</sub>, q<sub>1</sub>}    | {q<sub>0</sub>}   |
|   q<sub>1</sub>   | &#8709;                           | {q<sub>1</sub>}   |
|  *q<sub>2</sub>   | &#8709;                           | &#8709;           |
{: .math}
```

|                   | 0                                 | 1                 |
|------------------:|:----------------------------------|:------------------|
| → q<sub>0</sub>   | {q<sub>0</sub>, q<sub>1</sub>}    | {q<sub>0</sub>}   |
|   q<sub>1</sub>   | &#8709;                           | {q<sub>1</sub>}   |
|  *q<sub>2</sub>   | &#8709;                           | &#8709;           |
{: .math}

</div>
~~~

## Templating

When processing files, Jekyll will look for [Liquid](https://shopify.github.io/liquid/) code, process
it, and expand the resulting file accordingly. This allows the use of typical programming constructs,
like conditionals or loops, as wells as [variables](https://jekyllrb.com/docs/variables/), some of
which are automatically defined by Jekyll.

```liquid
{%- raw -%}
<header id="post-header">
        {%- assign url = page.url | remove_first: "/" | split: "/" -%}
    <span id="post-header-url">
        <a href="/">..</a>/
        {%- for url_component in url -%}
            {%- assign href = href | append: "/" | append: url_component -%}
            {%- unless forloop.last -%}
        <a href="{{ href }}">{{ url_component }}</a>/
            {%- endunless -%}
        {%- endfor -%}
        {{ url.last}}
    </span>
    <span id="post-header-date">
        <time datetime="{{ page.date | date_to_xmlschema }}">{{ page.date | date: "%Y-%m-%d" }}</time>
    </span>
</header>
{% endraw %}
```

Liquid also makes code reuse possible by means of [includes](https://jekyllrb.com/docs/includes/) and
[layouts](https://jekyllrb.com/docs/layouts/). Includes allow encapsulating arbitrary HTML, like the
post header above, and inserting it into another file with the `include` directive. Layouts, on the
other hand, define a wrapper around a content, and some other file can use the wrapper by referencing
it in the [Front Matter](https://jekyllrb.com/docs/front-matter/) section.

```liquid
{%- raw -%}
---
layout: default
---
{%- include post_header.html %}
<article>
    <h1 id="title">{{ page.title }}</h1>
    {{ content }}
</article>
{% endraw %}
```

## Style

Jekyll supports [Sass](https://sass-lang.com/), an extension of CSS, to define style sheets. Files
under the `_scss` directory are processed according to the Sass syntax, which provides functionality
such as [variables](https://sass-lang.com/documentation/variables/), or [modules](https://sass-lang.com/documentation/modules/)
on top of usual CSS rules. Sass proves quite useful for instance when dealing with a group of values
related through some function like shades of gray and `hsl`:

```scss
$gray-saturation: 10% !default;
$color-gray-darkest: hsl($theme-hue, $gray-saturation, 5%);
$color-gray-dark: hsl($theme-hue, $gray-saturation, 15%);
$color-gray-light: hsl($theme-hue, $gray-saturation, 30%);
$color-gray-lightest: hsl($theme-hue, $gray-saturation, 50%);
```

Syntax highlighting of code blocks is provided by [rouge](https://github.com/rouge-ruby/rouge), which
defines a number of [lexers](https://github.com/rouge-ruby/rouge/tree/master/lib/rouge/lexers) that
parse code into [tokens](https://github.com/rouge-ruby/rouge/blob/master/lib/rouge/token.rb). When
generating HTML code, each type of token is assigned a class that can be styled through CSS. All the
code above was generated by rouge with rules to only highlight names and literals. Here's a clearer
example in C[^rouge-c-lexer]:

```c
float rsqrt(float x)
{
    long i = *(long *)&x;
    i = 0x5f3759df - (i >> 1);
    float y = *(float *)&i;

    return y * (1.5f - (x * 0.5f * y * y));
}
```

---

[^github-pages-plugins]:
    In addition to [whitelisting](https://github.com/github/pages-gem/blob/v228/lib/github-pages/configuration.rb#L53)
    few plugins, the GitHub Pages ruby gem also prevents execution of custom user plugins such as
    [hooks](https://jekyllrb.com/docs/plugins/hooks/) by [overriding](https://github.com/github/pages-gem/blob/v228/lib/github-pages/configuration.rb#L52)
    the default plugin directory name.

[^jekyll-markdown]:
    Other parsers and further [configuration](https://jekyllrb.com/docs/configuration/markdown/) are
    available as well. Default values for many of the setting can be found
    [here](https://jekyllrb.com/docs/configuration/default/).

[^rouge-c-lexer]:
    At the time of writing, the [C lexer](https://github.com/rouge-ruby/rouge/blob/master/lib/rouge/lexers/c.rb)
    improperly parses floating point numbers due to an [invalid regex](https://github.com/rouge-ruby/rouge/blob/v4.1.3/lib/rouge/lexers/c.rb#L102).
