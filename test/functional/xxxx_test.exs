defmodule Ask.XXXXTest do
  use Ask.FunctionalTest

  test "respondent receives a message" do
    %{respondent: respondent} = setup_survey(mode: "sms")
    start_survey()
    assert_message_received respondent, "What's your age?"
  end
end


# ~~~~~~~~~

# %{respondent} = setup_survey(mode: "sms", timeouts: [2.hours])
# start_survey()
# assert_message_received respondent, "What's your age?"
# time_pass 2.hours
# assert_message_received respondent, "What's your age?"
