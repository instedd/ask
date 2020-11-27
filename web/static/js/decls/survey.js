// @flow
export type Folder = {
  id: number,
  name: string,
  projectId: number
}

export type Survey = {
  id: number,
  projectId: number,
  questionnaireIds: number[],
  questionnaires?: {[id: string]: Questionnaire},
  channels: number[],
  name: string,
  description: ?string,
  cutoff: ?number,
  countPartialResults: boolean,
  mode: string[][],
  modeComparison: boolean,
  state: string,
  locked: boolean,
  exitCode: ?number,
  exitMessage: ?string,
  questionnaireComparison: boolean,
  ivrRetryConfiguration: string,
  smsRetryConfiguration: string,
  mobilewebRetryConfiguration: string,
  fallbackDelay: string,
  schedule: Schedule,
  respondentsCount: number,
  quotas: {
    vars: string[],
    buckets: Bucket[]
  },
  links: Link[],
  comparisons: Comparison[],
  nextScheduleTime: ?string,
  isPanelSurvey: boolean
};

export type Link = {
  name: string,
  url: string
}

export type Schedule = {
  dayOfWeek: DayOfWeek,
  startTime: string,
  endTime: string,
  timezone: string,
  blockedDays: string[]
}

export type DayOfWeek = {
  [weekday: string]: boolean
};

export type SurveyPreview = {
  id: number,
  projectId: number,
  questionnaireIds: number[],
  channels: number[],
  name: string,
  mode: string[][],
  state: string,
  cutoff: ?number,
};

export type Comparison = {
  questionnaireId: number,
  mode: string[],
  ratio: ?number
};

export type Bucket = {
  condition: Condition[],
  quota: number
};

export type Condition = {
  store: string,
  value: string
};

export type QuotaVar = {
  var: string,
  steps?: string
};

export type PartialRelevant = {
  answeredCount: number
}

export type Respondent = {
  id: number,
  phoneNumber: string,
  mode: string[],
  disposition: Disposition,
  date: ?string,
  responses: Response[],
  questionnaireId: number,
  partialRelevant: PartialRelevant,
  stats: Stats
};

export type Attempts = {
  sms: number,
  ivr: number
};

export type Stats = {
  attempts: Attempts,
  totalSentSms: number,
  totalReceivedSms: number,
  totalCallTime: number
};

export type Integration = {
  id: number,
  name: string,
  uri: string,
  authToken: string,
  state: "enabled" | "terminated" | "disabled"
};

export type Response = {
  name: string,
  value: ?string
};

export type Disposition = null | "completed" | "partial" | "ineligible";
