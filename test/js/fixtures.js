// @flow
import deepFreeze from '../../web/static/vendor/js/deepFreeze'

const steps = [
  {
    type: 'multiple-choice',
    title: 'Do you smoke?',
    store: 'Smokes',
    id: '17141bea-a81c-4227-bdda-f5f69188b0e7',
    choices: [
      {
        value: 'Yes',
        responses: {
          sms: {
            en: [
              'Yes',
              'Y',
              '1'
            ],
            'es': [
              'Sí',
              'S',
              '1'
            ]
          },
          ivr: [
            '1'
          ],
          mobileweb: {
            'en': 'Of course',
            'es': 'Por supuesto'
          }
        },
        skipLogic: null
      },
      {
        value: 'No',
        responses: {
          sms: {
            'en': [
              'No',
              'N',
              '2'
            ],
            'es': [
              'No',
              'N',
              '2'
            ]
          },
          ivr: [
            '2'
          ],
          mobileweb: {
            'en': 'Not at all',
            'es': 'Para nada'
          }
        },
        skipLogic: 'b6588daa-cd81-40b1-8cac-ff2e72a15c15'
      }
    ],
    prompt: {
      'en': {
        sms: 'Do you smoke?',
        ivr: {
          text: 'Do you smoke?',
          audioSource: 'tts'
        },
        mobileweb: 'Do you really smoke?'
      },
      'es': {
        sms: 'Fumas?'
      }
    }
  },
  {
    type: 'multiple-choice',
    title: 'Do you exercise?',
    store: 'Exercises',
    id: 'b6588daa-cd81-40b1-8cac-ff2e72a15c15',
    choices: [
      {
        value: 'Yes',
        responses: {
          'en': {
            sms: [
              'Yes',
              'Y',
              '1'
            ],
            ivr: [
              '1'
            ]
          }
        },
        skipLogic: null
      },
      {
        value: 'No',
        responses: {
          'en': {
            sms: [
              'No',
              'N',
              '2'
            ],
            ivr: [
              '2'
            ]
          }
        },
        skipLogic: null
      }
    ],
    prompt: {
      'en': {
        sms: 'Do you exercise?'
      },
      'es': {
        sms: 'Ejercitas?'
      }
    }
  }
]

const questionnaireCommonFields = {
  quotaCompletedSteps: null,
  projectId: 1,
  name: 'Foo',
  modes: [
    'sms', 'ivr'
  ],
  id: 1,
  defaultLanguage: 'en',
  activeLanguage: 'en',
  activeMode: 'sms',
  languages: ['en'],
  settings: {
    errorMessage: {},
    mobileWebSmsMessage: '',
    mobileWebSurveyIsOverMessage: '',
    title: {},
    mobileWebColorStyle: {},
    surveyAlreadyTakenMessage: {}
  },
  valid: true,
  partialRelevantConfig: {}
}

const bareQuestionnaire: Questionnaire = {
  ...questionnaireCommonFields,
  steps: steps
}

const languageSelection = {
  id: '92283e47-fda4-4ac6-b968-b96fc921dd8d',
  type: 'language-selection',
  title: 'Language selection',
  store: '',
  prompt: {
    sms: '1 for English, 2 for Spanish',
    ivr: {
      text: '1 para ingles, 2 para español',
      audioSource: 'tts'
    }
  },
  languageChoices: ['en', 'es']
}

const quizWithLangSelection = {
  ...bareQuestionnaire,
  steps: [languageSelection, ...steps],
  languages: ['en', 'es']
}

const bareQuestionnaireWithSection: Questionnaire = {
  ...questionnaireCommonFields,
  name: 'Foo2',
  steps: [
    languageSelection,
    {
      type: 'section',
      title: 'Section 1',
      id: '4108b902-3af4-4c33-bb76-84c8e5029814',
      steps: steps,
      randomize: false
    }
  ]
}

const bareQuestionnaireWith2Sections: Questionnaire = {
  ...questionnaireCommonFields,
  name: 'Foo2',
  languages: ['en', 'es'],
  valid: false,
  steps: [
    languageSelection,
    {
      type: 'section',
      title: 'Section 1',
      id: '4108b902-3af4-4c33-bb76-84c8e5029814',
      steps: steps,
      randomize: false
    },
    {
      type: 'section',
      title: 'Section 2',
      id: '2a16c315-0fd6-457b-96ab-84d4bcd0ba42',
      steps: [
        {
          type: 'multiple-choice',
          title: 'Do you like this question?',
          store: 'likes',
          id: '9bf3a92d-e604-4af0-9f6b-6d42834a05a0',
          choices: [
            {
              value: 'Yes',
              responses: {
                'en': {
                  sms: [
                    'Yes',
                    'Y',
                    '1'
                  ],
                  ivr: [
                    '1'
                  ]
                }
              },
              skipLogic: null
            },
            {
              value: 'No',
              responses: {
                'en': {
                  sms: [
                    'No',
                    'N',
                    '2'
                  ],
                  ivr: [
                    '2'
                  ]
                }
              },
              skipLogic: null
            }
          ],
          prompt: {
            'en': {
              sms: 'Do you like this question?'
            },
            'es': {
              sms: 'Te gusta esta pregunta?'
            }
          }
        }],
      randomize: false
    }
  ]
}

const bareQuestionnaireWith3Sections: Questionnaire = {
  ...questionnaireCommonFields,
  languages: ['en', 'es'],
  steps: [
    languageSelection,
    {
      type: 'section',
      title: 'Section 1',
      id: '07B9C1A3-A605-4CBE-B874-400AED68D8FC',
      steps: steps,
      randomize: false
    },
    {
      type: 'section',
      title: 'Section 2',
      id: '8EEA2740-864B-48D8-9469-A722620C146E',
      steps: steps,
      randomize: false
    },
    {
      type: 'section',
      title: 'Section 3',
      id: 'E6816ED8-0ADD-459D-9E9E-43EA52E60769',
      steps: steps,
      randomize: false
    }
  ]
}

const bareQuestionnaireWith2SectionsAndNoLanguage: Questionnaire = {
  ...questionnaireCommonFields,
  languages: ['en', 'es'],
  steps: [
    {
      type: 'section',
      title: 'Section 1',
      id: '07B9C1A3-A605-4CBE-B874-400AED68D8FC',
      steps: steps,
      randomize: false
    },
    {
      type: 'section',
      title: 'Section 2',
      id: '8EEA2740-864B-48D8-9469-A722620C146E',
      steps: steps,
      randomize: false
    }
  ]
}

// TODO: investigate why Flow ignores the result of `deepFreeze`
// It probably is defined as `any` somewhere.
// As a workaround, we define `bareQuestionnaire` and explicitly annotate it as
// Questionnaire. That will let us catch inconsistencies when we define the
// Questionnaire fixture for testing here.
// The limitations of deepFreeze are probably related to sealed objects being used under its hood.
// See: https://flowtype.org/docs/objects.html#sealed-object-types
export const questionnaire: Questionnaire = deepFreeze(bareQuestionnaire)

export const questionnaireWithSection: Questionnaire = deepFreeze(bareQuestionnaireWithSection)

export const questionnaireWith2Sections: Questionnaire = deepFreeze(bareQuestionnaireWith2Sections)

export const questionnaireWith3Sections: Questionnaire = deepFreeze(bareQuestionnaireWith3Sections)

export const questionnaireWith2SectionsAndNoLanguage: Questionnaire = deepFreeze(bareQuestionnaireWith2SectionsAndNoLanguage)

export const questionnaireWithLangSelection: Questionnaire = deepFreeze(quizWithLangSelection)

const bareSurvey: Survey = {
  id: 1,
  projectId: 1,
  name: 'Foo',
  description: null,
  cutoff: 123,
  countPartialResults: false,
  state: 'ready',
  locked: false,
  exitCode: 0,
  exitMessage: null,
  questionnaireIds: [1],
  schedule: {
    dayOfWeek: {'sun': true, 'mon': true, 'tue': true, 'wed': true, 'thu': true, 'fri': true, 'sat': true},
    startTime: '02:00:00',
    endTime: '06:00:00',
    timezone: 'Etc/UTC',
    blockedDays: []
  },
  channels: [1],
  respondentsCount: 2,
  comparisons: [],
  ivrRetryConfiguration: '',
  mobilewebRetryConfiguration: '',
  smsRetryConfiguration: '',
  fallbackDelay: '',
  modeComparison: false,
  questionnaireComparison: false,
  links: [],
  quotas: {
    vars: [],
    buckets: []
  },
  mode: [['sms']],
  nextScheduleTime: null,
  isPanelSurvey: false
}

const bareFolder: Folder = {
  id: 1,
  projectId: 1,
  name: 'Some name'
}

export const survey: Survey = deepFreeze(bareSurvey)
export const folder: Folder = deepFreeze(bareFolder)

const bareChannel: Channel = {
  id: 1,
  userId: 1,
  name: 'Channel Name',
  type: 'sms',
  projects: [],
  provider: 'nuntium',
  settings: {
    nuntiumChannel: 'Nuntium Channel Name'
  },
  patterns: [],
  errorsByPath: {}
}

export const channel: Channel = deepFreeze(bareChannel)

const bareProject: Project = {
  id: 1,
  name: 'Project Name',
  updatedAt: '2017-01-10T21:03:19',
  readOnly: false
}

export const project: Project = deepFreeze(bareProject)
