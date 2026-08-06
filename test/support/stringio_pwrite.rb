# frozen_string_literal: true

# StringIO has #pread but not #pwrite (true at least through Ruby 3.3),
# even though it's otherwise seekable and writable. Test fixtures throughout
# use StringIO as a lightweight, no-disk stand-in for a real file, so give
# it the one method it's missing rather than switching those tests to
# Tempfile. Real File already has both natively.
class StringIO
  def pwrite(bytes, offset)
    original_offset = tell
    seek(offset)
    write(bytes)
  ensure
    seek(original_offset)
  end
end
