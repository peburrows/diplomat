defmodule Diplomat.CursorTest do
  use ExUnit.Case

  alias Diplomat.Cursor

  @decoded_cursor_value <<255, 127, 254, 252>>

  describe "Cursor.new/1" do
    test "it create a new cursor" do
      assert %Cursor{value: "_3_-_A=="} = Cursor.new("_3_-_A==")
    end

    test "it returns a new Cursor with an encoded value with 'encode' flag" do
      assert %Cursor{value: "_3_-_A=="} = Cursor.new(@decoded_cursor_value, encode: true)
    end
  end

  describe "Cursor.encode/1" do
    test "encodes a cursor value into a base64 string" do
      assert "_3_-_A==" == Cursor.encode(@decoded_cursor_value)
    end
  end

  describe "Cursor.decode/1" do
    test "decodes a Cursor struct" do
      cursor = Cursor.new(@decoded_cursor_value, encode: true)

      assert @decoded_cursor_value == Cursor.decode(cursor)
    end

    test "decodes a base64 encoded cursor value" do
      assert @decoded_cursor_value == Cursor.decode("_3_-_A==")
    end
  end
end
