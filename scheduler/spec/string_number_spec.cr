require "spec"
require "../src/string_number"

describe StringNumber do

    describe "add" do
        it "add 1, 1 = 2" do
            result = StringNumber.add("1", "1")
            (result=="2").should be_true
        end

        it "add 11111111111111111111111111111111 , 1 = 11111111111111111111111111111112" do
            result = StringNumber.add("11111111111111111111111111111111", "1")
            (result=="11111111111111111111111111111112").should be_true
        end
    end

    describe "incr" do
        it "incr 11111111111111111111111111111111" do
            result = StringNumber.incr("11111111111111111111111111111111")
            (result=="11111111111111111111111111111112").should be_true
        end

        it "incr 11111111111111111111111111111111, 10" do
            result = StringNumber.incr("11111111111111111111111111111111", 10)
            (result=="11111111111111111111111111111121").should be_true
        end
    end

    describe "sub" do
        it "sub 11111111111111111111111111111111, 1 = 11111111111111111111111111111110" do
            result = StringNumber.sub("11111111111111111111111111111111", "1")
            (result=="11111111111111111111111111111110").should be_true
        end

        it "sub 11111111111111111111111111111111, 11111111111111111111111111111111 = 0" do
            result = StringNumber.sub("11111111111111111111111111111111", "11111111111111111111111111111111")
            (result=="0").should be_true
        end

        it "sub 1, 11 = -10" do
            result = StringNumber.sub("1", "11")
            (result=="-10").should be_true
        end

        it "sub 21, 11 = 10" do
            result = StringNumber.sub("21", "11")
            (result=="10").should be_true
        end
    end

    describe "gt" do
        it "gt 21, 11 = true" do
            result = StringNumber.gt("21", "11")
            result.should be_true
        end

        it "gt 100, 11 = true" do
            result = StringNumber.gt("100", "11")
            result.should be_true
        end

        it "gt 10, 21 = false" do
            result = StringNumber.gt("10", "21")
            result.should be_false
        end

        it "gt 0, 21 = false" do
            result = StringNumber.gt("0", "21")
            result.should be_false
        end

        it "gt 111, 111 = false" do
            result = StringNumber.gt("111", "111")
            result.should be_false
        end
    end

end