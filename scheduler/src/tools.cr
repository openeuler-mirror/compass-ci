module Public
    def self.hashReplaceWith(hashIn : Hash, hashR : Hash)
        keyname = hashR.keys[0]

        if hashIn[keyname]?
            hashIn.delete(keyname)
        end

        return hashR.merge(hashIn)
    end

    def self.getTestgroupName(testbox : String)
        tbox_group = testbox

        find = testbox.match(/(.*)(\-\d{1,}$)/)
        if find != nil
            tbox_group = find.not_nil![1]
        end

        return tbox_group
    end
end
