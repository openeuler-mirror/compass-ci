module StringNumber

    def self.add(left_decimal : String, right_decimal : String)
        left = left_decimal.reverse
        right = right_decimal.reverse

        ls = left.size
        rs = right.size
        maxLoop = (ls > rs) ? ls : rs

        carry = 0
        result = ""
        maxLoop.times do |index|
            lc = (index < ls) ? left[index] : '0'
            rc = (index < rs) ? right[index] : '0'
            add_lr = lc.to_i + rc.to_i + carry

            if add_lr > 9
                add_lr = add_lr - 9
                carry = 1
            end

            result = result + add_lr.to_s
        end
        if carry > 0
            result = result + carry.to_s
        end

        return result.reverse
    end

    def self.incr(left_decimal : String, number : Int32 = 1)
        return add(left_decimal, number.to_s)
    end

    def self.sub(left_decimal : String, right_decimal : String)
        if left_decimal == right_decimal
            return "0"
        end

        left = left_decimal.reverse
        right = right_decimal.reverse

        ls = left.size
        rs = right.size
        maxLoop = (ls > rs) ? ls : rs

        borrow = 0
        result = ""
        maxLoop.times do |index|
            lc = (index < ls) ? left[index] : '0'
            rc = (index < rs) ? right[index] : '0'
            sub_lr = lc.to_i - rc.to_i - borrow

            if sub_lr < 0
                sub_lr = sub_lr + 10
                borrow = 1
            end
            result = result + sub_lr.to_s
        end

        if borrow > 0
            return "-" + sub(right_decimal, left_decimal)
        end
        return result.reverse
    end

    def self.gt(left_decimal : String, right_decimal : String)
        if left_decimal == right_decimal
            return false
        end

        if left_decimal.size < right_decimal.size
            return false
        end

        if left_decimal.size > right_decimal.size
            return true
        end
        
        case sub(left_decimal, right_decimal)[0]
        when '-'
            return false
        else
            return true
        end
    end

end