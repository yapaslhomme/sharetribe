describe Util::HashUtils do
  it "#camelize_keys" do
    expected = {
      outerKey1: {
        innerKey1: {
          innerInnerKey1: "foo",
          innerInnerKey2: "bar"
        },
        innerKey2: "foo",
        innerKey3: "bar"
      },
      outerKey2: "foo"
    }

    test_data = {
      outer_key_1: {
        inner_key_1: {
          inner_inner_key_1: "foo",
          inner_inner_key_2: "bar"
        },
        inner_key_2: "foo",
        inner_key_3: "bar"
      },
      outer_key_2: "foo"
    }

    Util::HashUtils.camelize_keys(test_data).should eql(expected)
  end
end