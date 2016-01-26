[![Build Status](https://travis-ci.org/AngelList/protip.svg)](https://travis-ci.org/AngelList/protip)
-------

# Protip

Resources backed by protobuf messages.

Basic Usage
-----------

Define a protobuf message to represent the fields on your resource:

```
// my_resource_message.proto

message MyResourceMessage {
  optional int64 id = 1;
  optional string name = 2;
}
```

Then define your resource and use it like an `ActiveModel::Model`:

```
class MyResource
  include Protip::Resource
  resource actions: [:create, :update, :show, :index],
    message: MyResourceMessage
end

resource = MyResource.new(name: 'foo')
if resource.save
  puts "Saved with ID: #{resource.id}"
else
  puts resource.errors.full_messages.join("\n")
end
```

Developing
----------

To build message classes, you'll need to install the latest (currently
3.0.0-beta-2) version of [`protoc`](https://github.com/google/protobuf).

Build message classes: `rake compile`

Run tests: `rake test`

Releases follow [SemVer](http://semver.org/).
