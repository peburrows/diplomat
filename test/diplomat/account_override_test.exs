defmodule Diplomat.AccountOverrideTest do
  use ExUnit.Case
  require Diplomat
  
  test "Verify account overrides are applied correctly" do
    assert Diplomat.Client.diplomat_account() == nil
    r = Diplomat.with_account(:alternative_account_email) do
      assert Diplomat.Client.diplomat_account() == :alternative_account_email
      a = Diplomat.with_account(:alternative_account2_email) do
        assert Diplomat.Client.diplomat_account() == :alternative_account2_email
        :alpha
      end
      assert a == :alpha
      assert Diplomat.Client.diplomat_account() == :alternative_account_email
      b = Diplomat.with_account(:alternative_account3_email) do
        assert Diplomat.Client.diplomat_account() == :alternative_account3_email
        :beta
      end
      assert b == :beta
      assert Diplomat.Client.diplomat_account() == :alternative_account_email
      :omega
    end
    assert Diplomat.Client.diplomat_account() == nil
    assert r == :omega
  end
  
end
