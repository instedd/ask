// @flow
import React, { Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import * as questionnaireActions from '../../actions/questionnaire'
import SmsPrompt from './SmsPrompt'
import IvrPrompt from './IvrPrompt'
import MobileWebPrompt from './MobileWebPrompt'
import { getStepPromptSms, getStepPromptIvr, getStepPromptIvrText, getStepPromptMobileWeb } from '../../step'
import { promptTextPath, promptIvrAudioIdPath } from '../../questionnaireErrors'
import * as api from '../../api'
import propsAreEqual from '../../propsAreEqual'

type State = {
  stepPromptSms: string,
  smsOriginalValue: string,
  ivrOriginalValue: string,
  stepPromptIvrText: string,
  stepPromptIvr: AudioPrompt,
  stepPromptMobileWeb: string,
  mobileWebOriginalValue: string
};

type Props = {
  step: Step,
  stepIndex: number,
  questionnaireActions: any,
  questionnaire: Questionnaire,
  readOnly: boolean,
  errors: Errors,
  classes: string,
  title?: string
};

class StepPrompts extends Component {
  state: State
  props: Props
  autocompleteItems: AutocompleteItem[]

  static defaultProps = {
    classes: ''
  }

  constructor(props) {
    super(props)
    this.state = this.stateFromProps(props)
  }

  stepPromptSmsChange(text) {
    this.setState({stepPromptSms: text})
  }

  stepPromptSmsSubmit(text) {
    this.props.questionnaireActions.changeStepPromptSms(this.props.step.id, text)
  }

  stepPromptMobileWebSubmit(text) {
    this.props.questionnaireActions.changeStepPromptMobileWeb(this.props.step.id, text)
  }

  stepPromptIvrChange(e) {
    e.preventDefault()
    this.setState({stepPromptIvrText: e.target.value})
  }

  stepPromptIvrSubmit(e) {
    e.preventDefault()
    const { step } = this.props
    this.props.questionnaireActions.changeStepPromptIvr(step.id, {
      text: e.target.value,
      audioSource: this.state.stepPromptIvr.audioSource
    })
  }

  stepPromptMobileWebChange(text) {
    this.setState({stepPromptMobileWeb: text})
  }

  changeIvrMode(e, mode) {
    const { step } = this.props
    this.props.questionnaireActions.changeStepPromptIvr(step.id, {text: this.state.stepPromptIvrText, audioSource: mode})
  }

  componentWillReceiveProps(newProps) {
    if (propsAreEqual(this.props, newProps)) return

    this.setState(this.stateFromProps(newProps))
  }

  stateFromProps(props) {
    const { step, questionnaire } = props
    const lang = questionnaire.activeLanguage

    return {
      stepPromptSms: getStepPromptSms(step, lang),
      smsOriginalValue: getStepPromptSms(step, lang),
      ivrOriginalValue: getStepPromptIvrText(step, lang),
      stepPromptIvr: getStepPromptIvr(step, lang),
      stepPromptIvrText: getStepPromptIvrText(step, lang),
      stepPromptMobileWeb: getStepPromptMobileWeb(step, lang),
      mobileWebOriginalValue: getStepPromptMobileWeb(step, lang)
    }
  }

  autocompletePromptGetData(value, callback, mode) {
    const { step, questionnaire } = this.props

    const defaultLanguage = questionnaire.defaultLanguage
    const activeLanguage = questionnaire.activeLanguage

    if (activeLanguage == defaultLanguage) {
      api.autocompletePrimaryLanguage(questionnaire.projectId, mode, 'prompt', defaultLanguage, value)
      .then(response => {
        const items = response.map(r => ({id: r.text, text: r.text, translations: r.translations}))
        this.autocompleteItems = items
        callback(value, items)
      })
    } else {
      let promptValue
      if (mode == 'sms') {
        promptValue = getStepPromptSms(step, defaultLanguage)
      } else {
        promptValue = getStepPromptIvrText(step, defaultLanguage)
      }
      if (promptValue.length == 0) return

      api.autocompleteOtherLanguage(questionnaire.projectId, mode, 'prompt', defaultLanguage, activeLanguage, promptValue, value)
      .then(response => {
        const items = response.map(r => ({id: r, text: r}))
        this.autocompleteItems = items
        callback(value, items)
      })
    }
  }

  autocompletePromptOnSelect(item, mode) {
    const { step, questionnaire } = this.props

    const defaultLanguage = questionnaire.defaultLanguage
    const activeLanguage = questionnaire.activeLanguage

    if (activeLanguage == defaultLanguage) {
      let value = this.autocompleteItems.find(i => i.id == item.id)
      if (mode == 'sms') {
        this.props.questionnaireActions.autocompleteStepPromptSms(step.id, value)
      } else {
        this.props.questionnaireActions.autocompleteStepPromptIvr(step.id, value)
      }
    } else {
      if (mode == 'sms') {
        this.props.questionnaireActions.changeStepPromptSms(step.id, item.text)
      } else {
        let prompt = getStepPromptIvr(step, activeLanguage)
        this.props.questionnaireActions.changeStepPromptIvr(step.id, {...prompt, text: item.text})
      }
    }
  }

  render() {
    const { step, stepIndex, questionnaire, readOnly, errors, classes, title } = this.props

    const activeLanguage = questionnaire.activeLanguage
    const sms = questionnaire.modes.indexOf('sms') != -1
    const ivr = questionnaire.modes.indexOf('ivr') != -1
    const mobileWeb = questionnaire.modes.indexOf('mobileWeb') != -1
    const autocomplete = step.type != 'language-selection'

    let smsInput = null
    if (sms) {
      let smsInputErrors = errors[promptTextPath(stepIndex, 'sms', activeLanguage)]
      smsInput = <SmsPrompt id='step_editor_sms_prompt'
        originalValue={this.state.smsOriginalValue}
        value={this.state.stepPromptSms}
        inputErrors={smsInputErrors}
        readOnly={readOnly}
        onChange={text => this.stepPromptSmsChange(text)}
        onBlur={text => this.stepPromptSmsSubmit(text)}
        autocomplete={autocomplete}
        autocompleteGetData={(value, callback) => this.autocompletePromptGetData(value, callback, 'sms')}
        autocompleteOnSelect={item => this.autocompletePromptOnSelect(item, 'sms')}
        />
    }

    let ivrInput = null
    if (ivr) {
      let ivrInputErrors = errors[promptTextPath(stepIndex, 'ivr', activeLanguage)]
      let ivrAudioIdErrors = errors[promptIvrAudioIdPath(stepIndex, activeLanguage)]
      ivrInput = <IvrPrompt id='step_editor_ivr_prompt'
        key={`${questionnaire.activeLanguage}-ivr-prompt`}
        value={this.state.stepPromptIvrText}
        originalValue={this.state.ivrOriginalValue}
        inputErrors={ivrInputErrors}
        audioIdErrors={ivrAudioIdErrors}
        readOnly={readOnly}
        onChange={e => this.stepPromptIvrChange(e)}
        onBlur={e => this.stepPromptIvrSubmit(e)}
        autocomplete={autocomplete}
        autocompleteGetData={(value, callback) => this.autocompletePromptGetData(value, callback, 'ivr')}
        autocompleteOnSelect={item => this.autocompletePromptOnSelect(item, 'ivr')}
        changeIvrMode={(e, mode) => this.changeIvrMode(e, mode)}
        stepId={step.id} ivrPrompt={this.state.stepPromptIvr}
        />
    }

    let mobileWebInput = null
    if (mobileWeb) {
      let mobileWebInputErrors = errors[promptTextPath(stepIndex, 'mobileWeb', activeLanguage)]
      mobileWebInput = <MobileWebPrompt id='step_editor_mobile_web_prompt'
        key={`${questionnaire.activeLanguage}-mobile-web-prompt`}
        value={this.state.stepPromptMobileWeb}
        originalValue={this.state.mobileWebOriginalValue}
        inputErrors={mobileWebInputErrors}
        readOnly={readOnly}
        onChange={text => this.stepPromptMobileWebChange(text)}
        onBlur={text => this.stepPromptMobileWebSubmit(text)}
        autocomplete={autocomplete}
        stepId={step.id}
        />
    }

    return (
      <li className={`collection-item ${classes}`} key='prompts'>
        <div className='row'>
          <div className='col s12'>
            <h5>{title || 'Question Prompt'}</h5>
          </div>
        </div>
        {smsInput}
        {ivrInput}
        {mobileWebInput}
      </li>
    )
  }
}

const mapStateToProps = (state, ownProps) => ({
  questionnaire: state.questionnaire.data
})

const mapDispatchToProps = (dispatch) => ({
  questionnaireActions: bindActionCreators(questionnaireActions, dispatch)
})

export default connect(mapStateToProps, mapDispatchToProps)(StepPrompts)
