# frozen_string_literal: true

# StringIO has #pread but not #pwrite. Add it so that tests can use StringIO
# instead of Tempfile.
class StringIO
  def pwrite(bytes, offset)
    original_offset = tell
    seek(offset)
    write(bytes)
  ensure
    seek(original_offset)
  end
end
