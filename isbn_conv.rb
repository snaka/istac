#
# iStac
# ISBN13 -> 10 (ASIN) converter
#
# Convert specification
#  <To do describe convert specification here>
#
# Convert example:
#   ISBN13: 978  479810941  1
#           (a)  (b)       (c)
#
#   ISBN10: 479810941  X
#           (b)       (c)
#
#   (a)Regional code / (b)Item code / (c)Check degit
# 
# @see http://www.marusankakusikaku.jp/archives/2007/01/06-isbn-asin.html
#

module ISBNConverter

  def conv_isbn13to10(isbn13)
    # No need to convert
    return isbn13 if isbn13.length == 10

    validate(isbn13)

    check_digit = make_check_digit(isbn13).to_s
    item_code_of(isbn13) + check_digit
  end
  
  # Validate for 
  def validate(isbn13)
    unless isbn13.length == 13
      raise ArgumentError, "ISBN-13's length expected 13 but was #{isbn13.length}"
    end
    unless regional_code_of(isbn13) == '978'
      raise ArgumentError, "ISBN-13's first 3 digit expected '978'"
    end
  end

  #------
  private
  
  # Base part of ISBN13
  def item_code_of(isbn13)
    isbn13[3, 9]
  end

  # Regional part of ISBN13  
  def regional_code_of(isbn13)
    isbn13[0, 3]
  end

  # Calculate check digit for ISBN-10
  def make_check_digit(isbn13) 
    weight = 10
    sum = 0
    
    base_digits = item_code_of(isbn13).split('').map {|a| a.to_i}
    base_digits.each do |digit|
      sum += digit * weight
      weight = weight - 1
    end
    
    result = 11 - sum % 11 
    return result == 10 ? 'X' : result.to_s 
  end
end

