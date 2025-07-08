Jekyll::Hooks.register :posts, :post_init do |post|
  puts "[*] Checking post #{ post.relative_path } for modifications"
  ncommits = `git rev-list --count HEAD "#{ post.path }"`

  if ncommits.to_i > 1
    last_modified = `git log -n 1 --pretty="%ad" --date=short "#{ post.path }"`.strip
    post.data['last_modified'] = last_modified
  end
end
