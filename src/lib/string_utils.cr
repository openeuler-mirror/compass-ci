class String
  def split_keep_left(delimiter)
    split(delimiter)[0..-2].join(delimiter) || self
  end
end
