json.extract! survey, :id, :name, :quiz_id, :created_at, :updated_at
json.url survey_url(survey, format: :json)