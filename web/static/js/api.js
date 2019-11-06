import { normalize, Schema, arrayOf } from 'normalizr'
import { camelizeKeys, decamelizeKeys } from 'humps'
import 'isomorphic-fetch'
import { upload } from './uploadManager'

const projectSchema = new Schema('projects')
const folderSchema = new Schema('folders')
const surveySchema = new Schema('surveys')
const questionnaireSchema = new Schema('questionnaires')
const respondentSchema = new Schema('respondents')
const respondentGroupSchema = new Schema('respondentGroups')
const responseSchema = new Schema('response')
const respondentsStatsSchema = new Schema('respondents')
const referenceSchema = new Schema('reference')
const channelSchema = new Schema('channels')
const audioSchema = new Schema('audios')
const activitySchema = new Schema('activities')
const integrationSchema = new Schema('integrations')

export class Unauthorized {
  constructor(response) {
    this.response = response
  }
}

surveySchema.define({
  channels: arrayOf(channelSchema)
})

responseSchema.define({
  channels: arrayOf(responseSchema)
})

const apiFetch = (url, options) => {
  return fetch(`/api/v1/${url}`, { ...options, credentials: 'same-origin' })
    .then(response => {
      return handleResponse(response, () =>
        response)
    })
}

const apiFetchJSON = (url, schema, options) => {
  return apiFetchJSONWithCallback(url, schema, options, commonCallback)
}

const apiFetchJSONWithCallback = (url, schema, options, responseCallback) => {
  return apiFetch(url, options)
      .then(response => {
        if (response.status == 204) {
          // HTTP 204: No Content
          return { json: null, response }
        } else {
          return response.json().then(json => ({ json, response }))
        }
      })
      .then(({ json, response }) => {
        return handleResponse(response, responseCallback(json, schema))
      })
}

const commonCallback = (json, schema) => {
  return () => {
    if (!json) { return null }
    if (json.errors) {
      console.log(json.errors)
    }
    if (schema) {
      return normalize(camelizeKeys(json.data), schema)
    } else {
      return json.data
    }
  }
}

const respondentsCallback = (json, schema) => {
  return () => {
    let normalized = normalize(camelizeKeys(json.data.respondents), schema)
    normalized.respondentsCount = parseInt(json.meta.count)
    return normalized
  }
}

const activitiesCallback = (json, schema) => {
  return () => {
    let normalized = normalize(camelizeKeys(json.data.activities), schema)
    normalized.activitiesCount = parseInt(json.meta.count)
    return normalized
  }
}

const handleResponse = (response, callback) => {
  if (response.ok) {
    return callback()
  } else if (response.status == 401 || response.status == 403) {
    return Promise.reject(new Unauthorized(response.statusText))
  } else {
    return Promise.reject(response)
  }
}

const apiPutOrPostJSON = (url, schema, verb, body) => {
  return apiPutOrPostJSONWithCallback(url, schema, verb, body, commonCallback)
}

const apiPutOrPostJSONWithCallback = (url, schema, verb, body, callback) => {
  const options = {
    method: verb,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    }
  }
  if (body) {
    options.body = JSON.stringify(decamelizeKeys(body, { separator: '_' }))
  }
  return apiFetchJSONWithCallback(url, schema, options, callback)
}

const apiPostJSON = (url, schema, body) => {
  return apiPutOrPostJSON(url, schema, 'POST', body)
}

const apiPutJSON = (url, schema, body) => {
  return apiPutOrPostJSON(url, schema, 'PUT', body)
}

const apiDelete = (url) => {
  return apiFetch(url, {method: 'DELETE'})
}

const apiPostFile = (url, schema, file) => {
  return apiFetchJSON(url, schema, {
    method: 'POST',
    body: newFormData(file)
  })
}

const newFormData = (file) => {
  const formData = new FormData()
  formData.append('file', file)
  return formData
}

export const fetchProjects = (options) => {
  return apiFetchJSON(`projects?archived=${options['archived']}`, arrayOf(projectSchema))
}

export const fetchFolders = (projectId) => {
  return apiFetchJSON(`projects/${projectId}/folders`, arrayOf(folderSchema))
}

export const fetchSurveys = projectId => {
  return apiFetchJSON(`projects/${projectId}/surveys`, arrayOf(surveySchema))
}

export const fetchQuestionnaires = (projectId) => {
  return apiFetchJSON(`projects/${projectId}/questionnaires`, arrayOf(questionnaireSchema))
}

export const fetchQuestionnaire = (projectId, id) => {
  return apiFetchJSON(`projects/${projectId}/questionnaires/${id}`, questionnaireSchema)
}

export const fetchProject = (id) => {
  return apiFetchJSON(`projects/${id}`, projectSchema)
}

export const fetchSurvey = (projectId, id) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${id}`, surveySchema)
}

export const createProject = (project) => {
  return apiPostJSON('projects', projectSchema, { project })
}

export const leaveProject = (projectId) => {
  return apiPostJSON(`projects/${projectId}/leave`, projectSchema)
}

export const createFolder = (projectId, name) => {
  return apiPostJSON(`projects/${projectId}/folders`, folderSchema, {folder: {name}})
}

export const deleteFolder = (projectId, folderId) => {
  return apiDelete(`projects/${projectId}/folders/${folderId}`)
}

export const renameFolder = (projectId, folderId, name) => {
  return apiPostJSON(`projects/${projectId}/folders/${folderId}/set_name`, folderSchema, { name })
}

export const createSurvey = (projectId, folderId) => {
  const timezone = getTimezone()
  let data
  if (timezone) {
    data = {survey: {timezone, folderId: folderId}}
  } else {
    data = null
  }
  let folderPath = folderId ? `/folders/${folderId}` : ''
  return apiPostJSON(`projects/${projectId}${folderPath}/surveys`, surveySchema, data)
}

export const deleteSurvey = (projectId, survey) => {
  return apiDelete(`projects/${projectId}/surveys/${survey.id}`)
}

const getTimezone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  } catch (ex) {
    return null
  }
}

export const createAudio = (files) => {
  return apiPostFile('audios', audioSchema, files[0])
}

export const uploadRespondentGroup = (projectId, surveyId, files) => {
  return apiPostFile(`projects/${projectId}/surveys/${surveyId}/respondent_groups`,
    respondentGroupSchema, files[0])
}

export const addMoreRespondentsToGroup = (projectId, surveyId, groupId, file) => {
  return apiPostFile(`projects/${projectId}/surveys/${surveyId}/respondent_groups/${groupId}/add`,
    respondentGroupSchema, file)
}

export const replaceRespondents = (projectId, surveyId, groupId, file) => {
  return apiPostFile(`projects/${projectId}/surveys/${surveyId}/respondent_groups/${groupId}/replace`,
    respondentGroupSchema, file)
}

export const updateRespondentGroup = (projectId, surveyId, groupId, data) => {
  return apiPutJSON(`projects/${projectId}/surveys/${surveyId}/respondent_groups/${groupId}`, respondentGroupSchema, { respondentGroup: data })
}

export const removeRespondentGroup = (projectId, surveyId, groupId) => {
  return apiDelete(`projects/${projectId}/surveys/${surveyId}/respondent_groups/${groupId}`)
}

export const fetchRespondents = (projectId, surveyId, limit, page, sortBy, sortAsc) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/respondents/?limit=${limit}&page=${page}&sort_by=${sortBy}&sort_asc=${sortAsc}`, arrayOf(respondentSchema), {}, respondentsCallback)
}

export const fetchRespondentsStats = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/respondents/stats`, respondentsStatsSchema)
}

export const fetchRespondentGroups = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/respondent_groups`, arrayOf(respondentGroupSchema))
}

export const createQuestionnaire = (projectId, questionnaire) => {
  return apiPostJSON(`projects/${projectId}/questionnaires`, questionnaireSchema, { questionnaire })
}

export const updateProject = (project) => {
  return apiPutJSON(`projects/${project.id}`, projectSchema, { project })
}

export const updateProjectArchived = (project) => {
  return apiPutJSON(`projects/${project.id}/update_archived_status`, projectSchema, { project })
}

export const updateSurvey = (projectId, survey) => {
  return apiPutJSON(`projects/${projectId}/surveys/${survey.id}`, surveySchema, { survey })
}

export const setSurveyName = (projectId, surveyId, name) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/set_name`, null, { name })
}
export const setFolderId = (projectId, surveyId, folderId) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/set_folder_id`, null, { folderId: folderId || null })
}

export const setSurveyDescription = (projectId, surveyId, description) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/set_description`, null, { description })
}

export const updateSurveyLockedStatus = (projectId, surveyId, locked) => {
  return apiPutJSON(`projects/${projectId}/surveys/${surveyId}/update_locked_status`, surveySchema, { locked })
}

export const fetchChannels = () => {
  return apiFetchJSON(`channels`, arrayOf(channelSchema))
}

export const fetchProjectChannels = (projectId) => {
  return apiFetchJSON(`projects/${projectId}/channels`, arrayOf(channelSchema))
}

export const fetchChannel = (channelId) => {
  return apiFetchJSON(`channels/${channelId}`, channelSchema)
}

export const updateChannel = (channel) => {
  return apiPutJSON(`/channels/${channel.id}`, channelSchema, { channel })
}

export const createChannel = (provider, baseUrl, channel) => {
  return apiPostJSON(`channels`, channelSchema, { provider, baseUrl, channel })
}

export const updateQuestionnaire = (projectId, questionnaire) => {
  return apiPutJSON(`projects/${projectId}/questionnaires/${questionnaire.id}`,
    questionnaireSchema, { questionnaire })
}

export const deleteQuestionnaire = (projectId, questionnaire) => {
  return apiDelete(`projects/${projectId}/questionnaires/${questionnaire.id}`)
}

export const launchSurvey = (projectId, surveyId) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/launch`, surveySchema)
}

export const stopSurvey = (projectId, surveyId) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/stop`, surveySchema)
}

export const fetchTimezones = () => {
  return apiFetchJSONWithCallback(`timezones`, null, {}, (json, schema) => {
    return () => {
      return json
    }
  })
}

export const fetchAuthorizations = () => {
  return apiFetchJSONWithCallback(`authorizations`, null, {}, (json, _) => () => json)
}

export const deleteAuthorization = (provider, baseUrl, keepChannels = false) => {
  return apiDelete(`authorizations/${provider}?base_url=${encodeURIComponent(baseUrl)}&keep_channels=${keepChannels}`)
}

export const synchronizeChannels = () => {
  return apiFetch(`authorizations/synchronize`)
}

export const getUIToken = (provider, baseUrl) => {
  return apiFetch(`authorizations/ui_token?provider=${provider}&base_url=${encodeURIComponent(baseUrl)}`)
    .then(response => response.json())
}

export const autocompleteVars = (projectId, text) => {
  return apiFetch(`projects/${projectId}/autocomplete_vars?text=${encodeURIComponent(text)}`)
  .then(response => response.json())
}

export const autocompletePrimaryLanguage = (projectId, mode, scope, language, text) => {
  return apiFetch(`projects/${projectId}/autocomplete_primary_language?mode=${mode}&scope=${scope}&language=${language}&text=${encodeURIComponent(text)}`)
  .then(response => response.json())
  .catch(error => {
    console.log(error)
    return []
  })
}

export const autocompleteOtherLanguage = (projectId, mode, scope, primaryLanguage, otherLanguage, sourceText, targetText) => {
  return apiFetch(`projects/${projectId}/autocomplete_other_language?mode=${mode}&scope=${scope}&primary_language=${primaryLanguage}&other_language=${otherLanguage}&source_text=${encodeURIComponent(sourceText)}&target_text=${encodeURIComponent(targetText)}`)
  .then(response => response.json())
  .catch(error => {
    console.log(error)
    return []
  })
}

export const fetchCollaborators = (projectId) => {
  return apiFetchJSON(`projects/${projectId}/collaborators`)
}

export const removeCollaborator = (projectId, collaboratorEmail) => {
  return apiDelete(`projects/${projectId}/memberships/remove?email=${encodeURIComponent(collaboratorEmail)}`)
}

export const updateCollaboratorLevel = (projectId, collaboratorEmail, newLevel) => {
  return apiPutJSON(`projects/${projectId}/memberships/update`, {}, { email: collaboratorEmail, level: newLevel })
}

export const fetchActivities = (projectId, limit, page, sortBy, sortAsc) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/activities?limit=${limit}&page=${page}&sort_by=${sortBy}&sort_asc=${sortAsc}`, arrayOf(activitySchema), {}, activitiesCallback)
}

export const fetchSettings = () => {
  return apiFetchJSON(`settings`)
}

export const updateSettings = (params) => {
  return apiPostJSON(`update_settings`, {}, params)
}

export const getInviteByEmailAndProject = (projectId, email) => {
  return apiFetchJSON(`get_invite_by_email_and_project?project_id=${projectId}&email=${encodeURIComponent(email)}`)
}

export const invite = (projectId, code, level, email) => {
  return apiFetchJSON(`invite?project_id=${projectId}&code=${encodeURIComponent(code)}&email=${encodeURIComponent(email)}&level=${encodeURIComponent(level)}`)
}

export const inviteMail = (projectId, code, level, email) => {
  return apiFetchJSON(`send_invitation?project_id=${projectId}&code=${encodeURIComponent(code)}&email=${encodeURIComponent(email)}&level=${encodeURIComponent(level)}`)
}

export const fetchInvite = (code) => {
  return apiFetchJSON(`invite_show?code=${encodeURIComponent(code)}`)
}

export const removeInvite = (projectId, collaboratorEmail) => {
  return apiDelete(`invite_remove?project_id=${projectId}&email=${encodeURIComponent(collaboratorEmail)}`)
}

export const updateInviteLevel = (projectId, collaboratorEmail, newLevel) => {
  return apiPutJSON(`invite_update`, {}, { project_id: projectId, email: collaboratorEmail, level: newLevel })
}

export const confirm = (code) => {
  return apiFetchJSON(`accept_invitation?code=${encodeURIComponent(code)}`)
}

export const importQuestionnaireZip = (projectId, questionnaireId, file, onCompleted, onProgress, onAbort, onError) => {
  const url = `/api/v1/projects/${projectId}/questionnaires/${questionnaireId}/import_zip`
  const apiOnCompleted = (response) => {
    const questionnaireSchema = new Schema('questionnaires')
    response = JSON.parse(response)
    response = normalize(camelizeKeys(response.data), questionnaireSchema)
    const questionnaire = response.entities.questionnaires[response.result]
    onCompleted(questionnaire)
  }
  return upload(file, url, apiOnCompleted, onProgress, onAbort, onError)
}

export const simulateQuestionnaire = (projectId, questionnaireId, phoneNumber, mode, channelId) => {
  return apiPostJSON(`projects/${projectId}/surveys/simulate_questionanire?questionnaire_id=${questionnaireId}&phone_number=${encodeURIComponent(phoneNumber)}&mode=${encodeURIComponent(mode)}&channel_id=${encodeURIComponent(channelId)}`,
    surveySchema, {})
}

export const fetchSurveySimulationStatus = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/simulation_status`)
}

export const fetchSurveyStats = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/stats`)
}

export const fetchSurveyRetriesHistograms = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/retries_histograms`)
}

export const stopSurveySimulation = (projectId, surveyId) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/stop_simulation`, null, {})
}

const passthroughCallback = (json, _schema) => {
  return () => {
    if (!json) { return null }
    if (json.errors) {
      console.log(json.errors)
    }
    return camelizeKeys(json)
  }
}

export const createResultsLink = (projectId, surveyId) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/results`, arrayOf(referenceSchema), {}, passthroughCallback)
}

export const createIncentivesLink = (projectId, surveyId) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/incentives`, arrayOf(referenceSchema), {}, passthroughCallback)
}

export const createInteractionsLink = (projectId, surveyId) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/interactions`, arrayOf(referenceSchema), {}, passthroughCallback)
}

export const createDispositionHistoryLink = (projectId, surveyId) => {
  return apiFetchJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/disposition_history`, arrayOf(referenceSchema), {}, passthroughCallback)
}

export const refreshResultsLink = (projectId, surveyId) => {
  return apiPutOrPostJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/results`, arrayOf(referenceSchema), 'PUT', {}, passthroughCallback)
}

export const refreshIncentivesLink = (projectId, surveyId) => {
  return apiPutOrPostJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/incentives`, arrayOf(referenceSchema), 'PUT', {}, passthroughCallback)
}

export const refreshInteractionsLink = (projectId, surveyId) => {
  return apiPutOrPostJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/interactions`, arrayOf(referenceSchema), 'PUT', {}, passthroughCallback)
}

export const refreshDispositionHistoryLink = (projectId, surveyId) => {
  return apiPutOrPostJSONWithCallback(`projects/${projectId}/surveys/${surveyId}/links/disposition_history`, arrayOf(referenceSchema), 'PUT', {}, passthroughCallback)
}

export const deleteResultsLink = (projectId, surveyId) => {
  return apiDelete(`projects/${projectId}/surveys/${surveyId}/links/results`)
}

export const deleteIncentivesLink = (projectId, surveyId) => {
  return apiDelete(`projects/${projectId}/surveys/${surveyId}/links/incentives`)
}

export const deleteInteractionsLink = (projectId, surveyId) => {
  return apiDelete(`projects/${projectId}/surveys/${surveyId}/links/interactions`)
}

export const deleteDispositionHistoryLink = (projectId, surveyId) => {
  return apiDelete(`projects/${projectId}/surveys/${surveyId}/links/disposition_history`)
}

export const fetchIntegrations = (projectId, surveyId) => {
  return apiFetchJSON(`projects/${projectId}/surveys/${surveyId}/integrations`, arrayOf(integrationSchema))
}

export const createIntegration = (projectId, surveyId, integration) => {
  return apiPostJSON(`projects/${projectId}/surveys/${surveyId}/integrations`, integrationSchema, { integration })
}
