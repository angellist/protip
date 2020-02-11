# DEPRECATED

> This gem hasn't been meaningfully maintained since 2017-2018. The released gem will remain public, but no future development will be done outside the organization.

-------



[![Build Status](https://travis-ci.org/AngelList/protip.svg)](https://travis-ci.org/AngelList/protip)
-------

# Protip

Relatively painless protocol buffers in Ruby.

Basic Usage
-----------

Protip lets you get and set common
[well-known types](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf)
in your protobuf messages using high-level Ruby objects.

Given a protobuf message:

```protobuf
message MyMessage {
  google.protobuf.StringValue string = 1;
  google.protobuf.Timestamp timestamp = 2;
}
```

Manipulate it like:

```ruby
m = Protip.decorate(MyMessage.new)
m.string = 'bar'
m.string # => 'bar'
m.timestamp = Time.now

m.message # => updated MyMessage object
```

Using standard protobuf, you'd have to do something like:

```ruby
m = MyMessage.new
m.string = Google::Protobuf::StringValue.new(value: 'foo')
m.string.value #=> 'foo'

time = Time.now
message.timestamp = Google::Protobuf::Timestamp.new(
  seconds: time.to_i,
  nanos: (time.usec * 1000)
)
```

#### Supported messages

Protip has built-in support for the following well-known types:

- `google.protobuf.DoubleValue`
- `google.protobuf.FloatValue`
- `google.protobuf.Int64Value`
- `google.protobuf.UInt64Value`
- `google.protobuf.Int32Value`
- `google.protobuf.UInt32Value`
- `google.protobuf.BoolValue`
- `google.protobuf.StringValue`
- `google.protobuf.BytesValue`
- `google.protobuf.Timestamp`

As well as some additional types for enums and repeated-or-nil fields:

- `protip.messages.EnumValue` (for nullable enum fields)
- `protip.messages.RepeatedEnum`
- `protip.messages.RepeatedDouble`
- `protip.messages.RepeatedFloat`
- `protip.messages.RepeatedInt64`
- `protip.messages.RepeatedUInt64`
- `protip.messages.RepeatedInt32`
- `protip.messages.RepeatedUInt32`
- `protip.messages.RepeatedBool`
- `protip.messages.RepeatedString`
- `protip.messages.RepeatedBytes`

To reference these messages in your .proto files, pass the
[`definitions/`](definitions/) directory to `protoc` (accessible via
`File.join(Gem.loaded_specs['protip'].full_gem_path, 'definitions')`
in Ruby) during compilation and use any of:

```protobuf
import "google/protobuf/wrappers.proto";
import "google/protobuf/timestamp.proto";
import "protip/messages.proto";
```

Enum types
----------

`protip.messages.EnumValue` and `protip.messages.RepeatedEnum` both
require a custom option to convert between enum symbols and the
integral value used by the message.  You can use these types like:

```protobuf
message Foo {
  enum Bar { BAZ = 0; }
  protip.messages.EnumValue bar = 1 [(protip_enum) = "Foo.Bar"];
}
```

And then, in Ruby:

```ruby
m = Foo.new
m.bar = :BAZ
m.bar # => :BAZ
```

Pending resolution of a
[protobuf issue](https://github.com/google/protobuf/issues/1198), enum
support also requires that you use the `protip:compile` task provided
in [`protip/tasks/compile.rake`](lib/protip/tasks/compile.rake) when
compiling your .proto files.

Architecture
------------

`Protip.decorate` returns a `Protip::Decorator` object, which
delegates getter/setter calls to its underlying message.

Getters/setters for message fields are filtered through a
`Protip::Transformer` instance, which defines `to_object` and
`to_message` to convert between Ruby objects and representative
protobuf messages.

By default, `Protip.default_transformer` is used for conversion. You
can add your own message transformations using:

```ruby
Protip.default_transformer['MyMessage'] = MyTransformer.new
```

`ActiveModel` resources
-----------------------

Protip includes support for persistable resources backed by protobuf
messages. The API here should be considered experimental.

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

Development
-----------

To build message classes, you'll need to install the latest version of
[`protoc`](https://github.com/google/protobuf).

Build message classes: `rake compile`

Run tests: `rake test`
