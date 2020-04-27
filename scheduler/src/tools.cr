module Public
    def self.hashReplaceWith(hashIn : Hash, hashR : Hash)
        keyname = hashR.keys[0]

        if hashIn[keyname]?
            hashIn.delete(keyname)
        end

        return hashR.merge(hashIn)
    end

    def self.getTestgroupName(testbox_name : String)
        testgroup_name = testbox_name

        find = testbox_name.match(/(.*)(\-\d{1,}$)/)
        if find != nil
            testgroup_name = find.not_nil![1]
        end

        return testgroup_name
    end
end