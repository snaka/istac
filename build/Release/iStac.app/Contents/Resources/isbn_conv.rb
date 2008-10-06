# isbn13 -> 10 (ASIN) converter

module ISBNConverter
  def conv_isbn13to10(isbn13)
    return isbn13 if isbn13.length == 10
    validate(isbn13)
   
    digits9 = digits(isbn13).join
    last_digit = check_d(make_sum(digits(isbn13))).to_s
    digits9 + last_digit
  end
  
  def validate(isbn13)
    unless isbn13.length == 13
      raise ArgumentError, "isbn13's length expected 13 but was #{isbn13.length}"
    end
    unless isbn13[0,3] == '978'
      raise ArgumentError, "isbn's first 3 digit expected '978'"
    end
  end

  private
  def digits(isbn13)
    isbn13[3, 9].each_char.map {|item| item.to_i}
  end

  def make_sum(digits)
    weights = 10.downto(2).to_a
    sum = 0
    digits.each_with_index {|item, i| sum += item * weights[i]}
    sum
  end

  def check_d(sum) 
    result = 11 - sum % 11 
    result = 'X' if result == 10
    return result
  end
end

