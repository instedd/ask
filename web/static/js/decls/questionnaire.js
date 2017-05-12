// @flow
export type Questionnaire = {
  name: string,
  steps: Step[],
  quotaCompletedSteps: ?(Step[]),
  modes: string[],
  languages: string[],
  defaultLanguage: string,
  activeLanguage: string,
  settings: Settings,
  projectId: number,
  valid: ?boolean
};

export type Settings = {
  errorMessage: Prompt,
  mobileWebSmsMessage: ?string,
  mobileWebSurveyIsOverMessage: ?string,
  mobileWebColorStyle?: ColorStylePrompt,
  title: {[lang: string]: string},
  surveyAlreadyTakenMessage: {[lang: string]: string},
  thankYouMessage?: Prompt,
};

export type ChoiceErrors = {
  value: string[],
  sms: string[],
  ivr: string[]
};

export type AudioPrompt = {
    audioSource: 'tts' | 'upload',
    text: string,
    audioId?: ?string
};

export type LanguagePrompt = {
  sms?: string,
  ivr?: AudioPrompt,
  mobileweb?: string
};

export type ColorStylePrompt = {
  primaryColor?: string,
  secondaryColor?: string
};

export type Prompt = { [lang: string]: LanguagePrompt };

export type MultipleChoiceStep = BaseStep & StoreStep & MultilingualStep & {
  type: 'multiple-choice',
  choices: Choice[]
};

export type LanguageSelectionStep = BaseStep & StoreStep & {
  type: 'language-selection',
  languageChoices: string[],
  prompt: LanguagePrompt
};

export type ExplanationStep = BaseStep & MultilingualStep & {
  type: 'explanation',
  skipLogic: ?string
};

export type FlagStep = BaseStep & {
  type: 'flag',
  disposition: 'completed' | 'partial' | 'ineligible',
  skipLogic: ?string
};

export type NumericStep = BaseStep & StoreStep & MultilingualStep & {
  type: 'numeric',
  minValue: ?number,
  maxValue: ?number,
  rangesDelimiters: ?string,
  ranges: Range[],
  refusal: ?Refusal
};

export type Refusal = {
  enabled: boolean,
  responses: {
    ivr?: string[],
    sms?: {
      [lang: string]: string[]
    },
    mobileweb?: {
      [lang: string]: string[]
    }
  },
  skipLogic: ?string
}

export type Range = {
  from: ?number,
  to: ?number,
  skipLogic: ?string
};

export type Choice = {
  value: string,
  skipLogic: ?string,
  responses: {
    ivr?: string[],
    sms?: {
      [lang: string]: string[]
    },
    mobileweb?: {
      [lang: string]: ?string
    }
  }
};

export type Step = LanguageSelectionStep | MultipleChoiceStep | NumericStep | ExplanationStep | FlagStep;
export type BaseStep = {
  id: string,
  title: string
};

export type StoreStep = {
  store: string
};

export type MultilingualStep = {
  prompt: Prompt
};

export type SkipOption = {
  id: string,
  title: string,
  enabled: boolean
};

export type Translation = {
  text: string,
  language: string
};

export type AutocompleteItem = {
  id: string,
  text: string,
  translations: Translation[]
};
