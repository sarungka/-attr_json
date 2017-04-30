require 'spec_helper'

RSpec.describe JsonAttribute::Record do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
    end
  end
  let(:instance) { klass.new }

  [
    [:integer, 12, "12"],
    [:string, "12", 12],
    [:decimal, BigDecimal.new("10.01"), "10.0100"],
    [:boolean, true, "t"],
    [:date, Date.parse("2017-04-28"), "2017-04-28"],
    [:datetime, DateTime.parse("2017-04-04 04:45:00").to_time, "2017-04-04T04:45:00Z"],
    [:float, 45.45, "45.45"]
  ].each do |type, cast_value, uncast_value|
    describe "for primitive type #{type}" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record

          self.table_name = "products"
          json_attribute :value, type
        end
      end
      it "properly saves good #{type}" do
        instance.value = cast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
      it "casts to #{type}" do
        instance.value = uncast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
    end
  end

  it "can set nil" do
    instance.str = nil
    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)

    instance.save!
    instance.reload

    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)
  end

  it "supports arrays" do
    instance.int_array = %w(1 2 3)
    expect(instance.int_array).to eq([1, 2, 3])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1, 2, 3])

    instance.int_array = 1
    expect(instance.int_array).to eq([1])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1])
  end

  # TODO: Should it LET you redefine instead, and spec for that? Have to pay
  # attention to store keys too if we let people replace attributes.
  it "raises on re-using attribute name" do
    expect {
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :value, :string
        json_attribute :value, :integer
      end
    }.to raise_error(ArgumentError, /Can't add, conflict with existing attribute name `value`/)
  end

  context "initialize" do
    it "casts and fills in defaults" do
      o = klass.new(int: "12", str: 12, int_array: "12")

      expect(o.int).to eq 12
      expect(o.str).to eq "12"
      expect(o.int_array).to eq [12]
      expect(o.int_with_default).to eq 5
      expect(o.json_attributes).to eq('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "assign_attributes" do
    it "casts" do
      instance.assign_attributes(int: "12", str: 12, int_array: "12")

      expect(instance.int).to eq 12
      expect(instance.str).to eq "12"
      expect(instance.int_array).to eq [12]
      expect(instance.json_attributes).to include('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "defaults" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :str_with_default, :string, default: "DEFAULT_VALUE"
      end
    end

    it "supports defaults" do
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
    end

    it "saves default even without access" do
      instance.save!
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
      instance.reload
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
    end

    it "lets default override with nil" do
      instance.str_with_default = nil
      expect(instance.str_with_default).to eq(nil)
      instance.save
      instance.reload
      expect(instance.str_with_default).to eq(nil)
      expect(instance.json_attributes).to include("str_with_default" => nil)
    end
  end

  context "store keys" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        include JsonAttribute::Record
        json_attribute :value, :string, default: "DEFAULT_VALUE", store_key: :_store_key
      end
    end

    it "puts the default value in the jsonb hash at the given store key" do
      expect(instance.value).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE")
    end

    it "sets the value at the given store key" do
      instance.value = "set value"
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")

      instance.save!
      instance.reload

      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    it "raises on conflicting store key" do
      expect {
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record

          self.table_name = "products"
          json_attribute :value, :string
          json_attribute :other_thing, :string, store_key: "value"
        end
      }.to raise_error(ArgumentError, /Can't add, store key `value` conflicts with existing attribute/)
    end

    context "inheritance" do
      let(:subklass) do
        Class.new(klass) do
          self.table_name = "products"
          include JsonAttribute::Record
          json_attribute :new_value, :integer, default: "NEW_DEFAULT_VALUE", store_key: :_new_store_key
        end
      end
      let(:subklass_instance) { subklass.new }

      it "includes default values from the parent in the jsonb hash with the correct store keys" do
        expect(subklass_instance.value).to eq("DEFAULT_VALUE")
        expect(subklass_instance.new_value).to eq("NEW_DEFAULT_VALUE")
        expect(subklass_instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE", "_new_store_key" => "NEW_DEFAULT_VALUE")
      end
    end
  end

  # time-like objects get super weird on edge cases, so they get their own
  # spec context.
  context "time-like objects" do
    let(:zone_under_test) { "America/Chicago" }
    around do |example|
      orig_tz = ENV['TZ']
      ENV['TZ'] = zone_under_test
      example.run
      ENV['TZ'] = orig_tz
    end

    # Make sure it has non-zero usecs for our tests, and freeze it
    # to make sure code under test does not mutate it.
    let(:datetime_value) { DateTime.now.change(usec: 555555).freeze }
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :json_datetime, :datetime
        json_attribute :json_time, :time
        json_attribute :json_time_array, :time, array: true
        json_attribute :json_datetime_array, :datetime, array: true
      end
    end

    context ":datetime type" do
      # 345123 to 345100
      def truncate_usec_to_ms(int)
        int.to_i / 1000 * 1000
      end

      before do
        instance.datetime_type = datetime_value
        instance.json_datetime = datetime_value
      end
      it "has the same class and zone on create" do
        # AR doesn't cast or transform in any way here, so we shouldn't either.
        expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
        expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)
      end

      it "has the same microseconds on create" do
        # AR doesn't touch it in any way here, so we shouldn't either.
        expect(instance.json_datetime.usec).to eq(instance.datetime_type.usec)
      end
      it "has the same class and zone after save" do
        instance.save!

        expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
        expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)

        # It's actually a Time with zone UTC now, not a DateTime, don't REALLY
        # need to check for this, but if it changes AR may have changed enough
        # that we should pay attention -- failing here doesn't neccesarily
        # mean anything is wrong though, although we prob want OURs to be UTC.
        expect(instance.json_datetime.class).to eq(Time)
        expect(instance.json_datetime.zone).to eq("UTC")
      end
      it "rounds usec to ms after save" do
        instance.save!

        expect(instance.json_datetime.usec % 1000).to eq(0)

        expect(truncate_usec_to_ms(instance.json_datetime.usec)).to eq(truncate_usec_to_ms(instance.datetime_type.usec))
      end
      it "has the same class and zone on fetch" do
        instance.save!

        new_instance = klass.find(instance.id)
        expect(new_instance.json_datetime.class).to eq(instance.datetime_type.class)
        expect(new_instance.json_datetime.zone).to eq(instance.datetime_type.zone)
      end

      describe "attributes_before_type_cast" do
        it "serializes as iso8601 in UTC with ms precision" do
          instance.json_datetime = datetime_value
          instance.save!

          json_serialized = JSON.parse(instance.json_attributes_before_type_cast)

          expect(json_serialized["json_datetime"]).to match /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d.\d{3}Z/
          expect(DateTime.iso8601(json_serialized["json_datetime"])).to eq(datetime_value.utc.change(usec: truncate_usec_to_ms(datetime_value.usec)))
        end
      end

      describe "to_json" do
        it "to_json's before save same as raw ActiveRecord" do
          to_json = JSON.parse(instance.to_json)
          expect(to_json["json_attributes"]["json_datetime"]).to eq to_json["datetime_type"]
        end
        it "to_json's after save same as raw ActiveRecord" do
          instance.save!
          to_json = JSON.parse(instance.to_json)
          expect(to_json["json_attributes"]["json_datetime"]).to eq to_json["datetime_type"]
        end
      end
    end
  end

  context "specified container_attribute" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        self.table_name = "products"

        json_attribute :value, :string, container_attribute: :other_attributes
      end
    end

    it "saves in appropriate place" do
      instance.value = "X"
      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank

      instance.save!
      instance.reload

      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank
    end

    describe "change default container attribute" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          self.table_name = "products"

          self.default_json_container_attribute = :other_attributes

          json_attribute :value, :string
        end
      end
      it "saves in right place" do
        instance.value = "X"
        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("value" => "X")
        expect(instance.json_attributes).to be_blank

        instance.save!
        instance.reload

        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("value" => "X")
        expect(instance.json_attributes).to be_blank
      end
    end

    describe "with store key" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          self.table_name = "products"

          json_attribute :value, :string, store_key: "_store_key", container_attribute: :other_attributes
        end
      end

      it "saves with store_key" do
        instance.value = "X"
        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank

        instance.save!
        instance.reload

        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank
      end

      describe "multiple containers with same store key" do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include JsonAttribute::Record
            self.table_name = "products"

            json_attribute :value, :string, store_key: "_store_key", container_attribute: :json_attributes
            json_attribute :other_value, :string, store_key: "_store_key", container_attribute: :other_attributes
          end
        end
        it "is all good" do
          instance.value = "value"
          instance.other_value = "other_value"

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")

          instance.save!
          instance.reload

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")
        end
        describe "with defaults" do
          let(:klass) do
            Class.new(ActiveRecord::Base) do
              include JsonAttribute::Record
              self.table_name = "products"

              json_attribute :value, :string, default: "value default", store_key: "_store_key", container_attribute: :json_attributes
              json_attribute :other_value, :string, default: "other value default", store_key: "_store_key", container_attribute: :other_attributes
            end
          end

          it "is all good" do
            expect(instance.value).to eq("value default")
            expect(instance.json_attributes).to eq("_store_key" => "value default")
            expect(instance.other_value).to eq("other value default")
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end

          it "fills default on direct set" do
            instance.json_attributes = {}
            expect(instance.json_attributes).to eq("_store_key" => "value default")

            instance.other_attributes = {}
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end
        end
      end
    end

    # describe "with bad attribute" do
    #   it "raises on decleration" do
    #     expect {
    #       Class.new(ActiveRecord::Base) do
    #         include JsonAttribute::Record
    #         self.table_name = "products"

    #         json_attribute :value, :string, container_attribute: :no_such_attribute
    #       end
    #     }.to raise_error(ArgumentError, /adfadf/)
    #   end
    # end

  end


end