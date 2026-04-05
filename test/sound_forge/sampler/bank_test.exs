defmodule SoundForge.Sampler.BankTest do
  use ExUnit.Case, async: true

  alias SoundForge.Sampler.Bank

  @valid_attrs %{name: "My Bank", user_id: 1}

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = Bank.changeset(%Bank{}, @valid_attrs)
      assert changeset.valid?
    end

    test "rejects nil name" do
      changeset = Bank.changeset(%Bank{}, %{@valid_attrs | name: nil})
      refute changeset.valid?
    end

    test "omitting name uses default (Bank A)" do
      changeset = Bank.changeset(%Bank{}, Map.delete(@valid_attrs, :name))
      assert changeset.valid?
    end

    test "requires user_id" do
      changeset = Bank.changeset(%Bank{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "validates name max length 100" do
      long_name = String.duplicate("a", 101)
      changeset = Bank.changeset(%Bank{}, %{@valid_attrs | name: long_name})
      refute changeset.valid?
    end

    test "100-char name is valid" do
      name_100 = String.duplicate("a", 100)
      changeset = Bank.changeset(%Bank{}, %{@valid_attrs | name: name_100})
      assert changeset.valid?
    end

    test "accepts optional color" do
      changeset = Bank.changeset(%Bank{}, Map.put(@valid_attrs, :color, "#ff0000"))
      assert changeset.valid?
    end

    test "accepts optional position" do
      changeset = Bank.changeset(%Bank{}, Map.put(@valid_attrs, :position, 3))
      assert changeset.valid?
    end

    test "accepts optional bpm" do
      changeset = Bank.changeset(%Bank{}, Map.put(@valid_attrs, :bpm, 120.0))
      assert changeset.valid?
    end
  end

  describe "defaults" do
    test "name defaults to Bank A" do
      bank = %Bank{}
      assert bank.name == "Bank A"
    end

    test "color defaults to purple" do
      bank = %Bank{}
      assert bank.color == "#8b5cf6"
    end

    test "position defaults to 0" do
      bank = %Bank{}
      assert bank.position == 0
    end
  end
end
