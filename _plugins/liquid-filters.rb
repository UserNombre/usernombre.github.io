require "uri"

module Jekyll
  module SourceCodeFilter
    attr_accessor :repositories
    attr_accessor :definitions
    attr_accessor :codepaths
    attr_accessor :tab_width
    attr_accessor :last_repository
    attr_accessor :debug

    def configure_sourcecode_data(yaml)
      normalize_yaml(yaml)
      self.repositories = yaml["repositories"]
      self.definitions = yaml["definitions"]
      self.codepaths = yaml["codepaths"]
      return ""
    end

    def generate_definition_link(name)
      html = ""
      if self.definitions.include?(name)
        definition = self.definitions[name]
        repository = self.repositories[definition["repository"]]
        if definition.include?("symbol")
            name = definition["symbol"]
        end

        url = repository["format"]
          .gsub("${file}", definition["file"])
          .gsub("${line}", definition["line"].to_s)
        html = "<a href='#{url}'><code>#{name}</code></a>"
      end
      return html
    end

    def generate_file_link(content, repository, file, line = nil)
      html = ""
      if self.repositories.include?(repository)
        content = content.empty? ? file : content
        repository = self.repositories[repository]
        if line == nil
          url = repository["format"]
            .gsub(/\$\{file\}.*/, file)
        else
          url = repository["format"]
            .gsub("${file}", file)
            .gsub("${line}", line.to_s)
        end
        html = "<a href='#{url}'>#{content}</a>"
      end
      return html
    end

    def generate_codepath(name, width = 4)
      self.tab_width = width
      self.last_repository = nil
      self.debug = ENV["JEKYLL_ENV"] == "development"
      if self.debug
        puts "Generating codepath for #{name}"
      end
      inner = generate_lines(nil, self.codepaths[name], 0)
      html = "<div class='highlighter-rouge unselectable'><pre><code>#{inner}</code></pre></div>"
      return html
    end

    private

    def normalize_yaml(yaml)
      yaml["codepaths"]&.each do |key, codepath|
        normalize_codepath(codepath)
      end
    end

    def normalize_codepath(codepath)
      codepath&.each do |node|
        node["line"] = node.fetch("line", nil)
        node["call"] = node.fetch("call", nil)
        node["code"] = node.fetch("code", nil)
        node["comment"] = node.fetch("comment", nil)
        node["footnote"] = node.fetch("footnote", nil)
        node["highlight"] = node.fetch("highlight", [])
        if node["highlight"].is_a?(String)
          node["highlight"] = [node["highlight"]]
        elsif not node["highlight"].is_a?(Array)
          node["highlight"] = ["foreground"]
        end
        node["children"] = node.fetch("children", [])
        normalize_codepath(node["children"])
      end
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
        if node["children"]
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
      if node["call"] && self.definitions[node["call"]] == nil
        puts "Invalid key '#{node["call"]}'"
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
      if parent == nil or node["line"] == nil
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
      if node["code"]
        html = node["code"]
      elsif node["call"]
        definition = self.definitions[node["call"]]
        html = definition.dig("symbol") || node["call"]
      end
      attributes = {:class => []}
      attributes[:class] << ["selectable"]
      if node["highlight"].include?("foreground")
        attributes[:class] << "codepath-hl-fg"
      elsif node["highlight"].include?("background")
        attributes[:class] << "codepath-hl-bg"
      end
      # FIXME: comment/footnotes style
      # https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Roles/tooltip_role#escape
      if node["comment"]
        attributes[:title] = node["comment"]
      end
      attributes = attributes.map{|k,v| "#{k.to_s}='#{v.is_a?(Array) ? v.join(" ") : v}'"}
      html = "<span #{attributes.join(" ")}>#{html}</span>"
      if node["footnote"]
        html += "<span markdown='1'>[^#{node["footnote"]}]</span>"
      end
      return html
    end

    def generate_definition(parent, node)
      html = ""
      if node["call"]
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

  module ResourceFilter
    def generate_resource(uri, resource = nil, source = nil)
      uri = URI.parse(uri)
      resource ||= uri.path.split("/").last
      source ||= uri.host
      return "<a href='#{uri}'>#{resource}</a>, #{source}"
    end
  end
end

Liquid::Template.register_filter(Jekyll::SourceCodeFilter)
Liquid::Template.register_filter(Jekyll::ResourceFilter)
