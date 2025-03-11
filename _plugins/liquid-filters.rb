module Jekyll
  module CodepathFilter
    attr_accessor :repositories
    attr_accessor :definitions
    attr_accessor :tab_width
    attr_accessor :last_repository
    attr_accessor :debug

    def generate_codepath(name, yaml, width)
      self.repositories = yaml["repositories"]
      self.definitions = yaml["definitions"]
      self.tab_width = width
      self.last_repository = nil
      self.debug = ENV["JEKYLL_ENV"] == "development"
      if self.debug
        puts "Generating codepath for #{name}"
      end
      inner = generate_lines(nil, yaml["codepaths"][name], 0)
      html = "<div class='highlighter-rouge unselectable'><pre><code>#{inner}</code></pre></div>"
      return html
    end

    def generate_lines(parent, nodes, depth)
      html = ""
      nodes&.each do |node|
        if self.debug
          id = node&.dig("call") || node&.dig("code")
          puts "Generating line for #{id}"
        end
        line = generate_line(parent, node, depth)
        if line == nil
          return nil
        end
        html += "#{line}\n"
        if node.key?("children")
          lines = generate_lines(node, node["children"], depth + 1)
          if lines == nil
            return nil
          end
          html += lines
        end
      end
      return html
    end

    def generate_line(parent, node, depth)
      if node.key?("call") && self.definitions[node["call"]] == nil
        puts "Invalid key #{node["call"]}"
        return nil
      end
      html = ""
      html += generate_indentation(parent, node, depth)
      html += generate_code(parent, node)
      html += generate_definition(parent, node)
      return html
    end

    def generate_indentation(parent, node, depth)
      html = ""
      if parent == nil or not node.key?("line")
        html = " " * self.tab_width * depth
      else
        html = " " * self.tab_width * (depth - 1)
        definition = self.definitions[parent["call"]]
        repository = self.repositories[definition["repository"]]
        url = repository["format"]
          .gsub("${file}", definition["file"])
          .gsub("${line}", node["line"].to_s)
        html += "<a href='#{url}'>>#{" " * (self.tab_width - 1)}</a>"
      end
      return html
    end

    def generate_code(parent, node)
      html = ""
      if node.key?("code")
        html = node["code"]
      elsif node.key?("call")
        definition = self.definitions[node["call"]]
        html = definition.dig("symbol") || node["call"]
      end
      classes = ["selectable"]
      if node.key?("highlight")
        classes << "relevant"
      end
      html = "<span class='#{classes.join(" ")}'>#{html}</span>"
      # FIXME: comment/footnotes style
      # https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Roles/tooltip_role#escape
      if node.key?("comment")
        html = "<span title='#{node["comment"]}'>#{html}</span>"
      end
      if node.key?("footnote")
        html += "<span markdown='1'>[^#{node["footnote"]}]</span>"
      end
      return html
    end

    def generate_definition(parent, node)
      html = ""
      if node.key?("call")
        definition = self.definitions[node["call"]]
        repository = self.repositories[definition["repository"]]
        url = repository["format"]
          .gsub("${file}", definition["file"])
          .gsub("${line}", definition["line"].to_s)
        path = definition["file"]
        # TODO: check parent repository instead of last
        if self.last_repository != definition["repository"]
          path += "@#{definition["repository"]}"
        end
        html = " <<a href='#{url}'>#{path}</a>>"
        self.last_repository = definition["repository"]
      end
      return html
    end
  end
end

Liquid::Template.register_filter(Jekyll::CodepathFilter)
