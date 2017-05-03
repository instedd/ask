import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { Card } from '../ui'
import SmsPrompt from './SmsPrompt'
import MobileWebPrompt from './MobileWebPrompt'
import classNames from 'classnames'
import propsAreEqual from '../../propsAreEqual'
import { getPromptMobileWeb } from '../../step'
import * as actions from '../../actions/questionnaire'

class WebSettings extends Component {
  constructor(props) {
    super(props)
    this.state = this.stateFromProps(props, false)
  }

  handleClick(e) {
    e.preventDefault()
    this.setState({editing: !this.state.editing})
  }

  componentWillReceiveProps(newProps) {
    if (propsAreEqual(this.props, newProps)) return

    this.setState(this.stateFromProps(newProps))
  }

  stateFromProps(props) {
    return {
      quotaCompletedMessage: props.quotaCompletedMessage,
      errorMessage: props.errorMessage,
      thankYouMessage: props.thankYouMessage,
      title: props.title,
      smsMessage: props.smsMessage,
      surveyIsOverMessage: props.surveyIsOverMessage,
      surveyAlreadyTakenMessage: props.surveyAlreadyTakenMessage
    }
  }

  messageChange(text, key) {
    this.setState({[key]: text})
  }

  messageBlur(text, key) {
    this.props.dispatch(actions.setMobileWebQuestionnaireMsg(key, text))
  }

  titleBlur(text) {
    this.props.dispatch(actions.setDisplayedTitle(text))
  }

  smsMessageBlur(text) {
    this.props.dispatch(actions.setMobileWebSmsMessage(text))
  }

  surveyIsOverMessageBlur(text) {
    this.props.dispatch(actions.setMobileWebSurveyIsOverMessage(text))
  }

  surveyAlreadyTakenMessageBlur(text) {
    this.props.dispatch(actions.setSurveyAlreadyTakenMessage(text))
  }

  collapsed() {
    let hasErrors = this.hasErrors()

    const iconClass = classNames({
      'material-icons left': true,
      'text-error': hasErrors
    })

    return (
      <div className='row'>
        <ul className='collapsible dark'>
          <li>
            <Card>
              <div className='card-content closed-step'>
                <a className='truncate' href='#!' onClick={(e) => this.handleClick(e)}>
                  <i className={iconClass}>build</i>
                  <span className={classNames({'text-error': hasErrors})}>Web settings</span>
                  <i className={classNames({'material-icons right grey-text': true, 'text-error': hasErrors})}>expand_more</i>
                </a>
              </div>
            </Card>
          </li>
        </ul>
      </div>
    )
  }

  expanded() {
    return (
      <div className='row'>
        <Card className='z-depth-0'>
          <ul className='collection collection-card dark'>
            <li className='collection-item header'>
              <div className='row'>
                <div className='col s12'>
                  <i className='material-icons left'>build</i>
                  <a className='page-title truncate'>
                    <span>Web settings</span>
                  </a>
                  <a className='collapse right' href='#!' onClick={(e) => this.handleClick(e)}>
                    <i className='material-icons'>expand_less</i>
                  </a>
                </div>
              </div>
            </li>
            <li className='collection-item'>
              {this.quotaCompletedMessageComponent()}
            </li>
            <li className='collection-item'>
              {this.errorMessageComponent()}
            </li>
            <li className='collection-item'>
              {this.thankYouMessageComponent()}
            </li>
            <li className='collection-item'>
              {this.titleComponent()}
            </li>
            <li className='collection-item'>
              {this.smsMessageComponent()}
            </li>
            <li className='collection-item'>
              {this.surveyIsOverMessageComponent()}
            </li>
            <li className='collection-item'>
              {this.surveyAlreadyTakenMessageComponent()}
            </li>
          </ul>
        </Card>
      </div>
    )
  }

  quotaCompletedMessageComponent() {
    return <MobileWebPrompt id='web_settings_quota_completed'
      label='Quota completed message'
      inputErrors={this.messageErrors('quotaCompletedMessage')}
      value={this.state.quotaCompletedMessage}
      originalValue={this.state.quotaCompletedMessage}
      onChange={text => this.messageChange(text, 'quotaCompletedMessage')}
      onBlur={text => this.messageBlur(text, 'quotaCompletedMessage')}
      readOnly={this.props.readOnly}
      />
  }

  errorMessageComponent() {
    return <MobileWebPrompt id='web_settings_error'
      label='Error message'
      inputErrors={this.messageErrors('errorMessage')}
      value={this.state.errorMessage}
      originalValue={this.state.errorMessage}
      onChange={text => this.messageChange(text, 'errorMessage')}
      onBlur={text => this.messageBlur(text, 'errorMessage')}
      readOnly={this.props.readOnly}
      />
  }

  thankYouMessageComponent() {
    return <MobileWebPrompt id='web_settings_thank_you'
      label='Thank you message'
      inputErrors={this.messageErrors('thankYouMessage')}
      value={this.state.thankYouMessage}
      originalValue={this.state.thankYouMessage}
      onChange={text => this.messageChange(text, 'thankYouMessage')}
      onBlur={text => this.messageBlur(text, 'thankYouMessage')}
      readOnly={this.props.readOnly}
      />
  }

  titleComponent() {
    return <MobileWebPrompt id='web_settings_title'
      label='Title'
      inputErrors={this.titleErrors()}
      value={this.state.title}
      originalValue={this.state.title}
      onChange={text => this.messageChange(text, 'title')}
      onBlur={text => this.titleBlur(text)}
      readOnly={this.props.readOnly}
      />
  }

  smsMessageComponent() {
    return <SmsPrompt id='web_settings_sms_message'
      label='SMS message'
      inputErrors={this.smsMessageErrors()}
      value={this.state.smsMessage}
      originalValue={this.state.smsMessage}
      readOnly={this.props.readOnly}
      onChange={text => this.messageChange(text, 'smsMessage')}
      onBlur={text => this.smsMessageBlur(text)}
      fixedEndLength={20}
      />
  }

  surveyIsOverMessageComponent() {
    return <MobileWebPrompt id='web_settings_survey_is_over'
      label='"Survey is over" message'
      inputErrors={this.surveyIsOverMessageErrors()}
      value={this.state.surveyIsOverMessage}
      originalValue={this.state.surveyIsOverMessage}
      onChange={text => this.messageChange(text, 'surveyIsOverMessage')}
      onBlur={text => this.surveyIsOverMessageBlur(text)}
      readOnly={this.props.readOnly}
      />
  }

  surveyAlreadyTakenMessageComponent() {
    return <MobileWebPrompt id='web_settings_survey_already_taken'
      label='"Survey already taken" message'
      inputErrors={this.surveyAlreadyTakenMessageErrors()}
      value={this.state.surveyAlreadyTakenMessage}
      originalValue={this.state.surveyAlreadyTakenMessage}
      onChange={text => this.messageChange(text, 'surveyAlreadyTakenMessage')}
      onBlur={text => this.surveyAlreadyTakenMessageBlur(text)}
      readOnly={this.props.readOnly}
      />
  }

  messageErrors(key) {
    const { questionnaire, errorsByPath } = this.props
    return errorsByPath[`${key}.prompt['${questionnaire.activeLanguage}'].mobileweb`]
  }

  titleErrors() {
    const { questionnaire, errorsByPath } = this.props
    return errorsByPath[`title['${questionnaire.activeLanguage}']`]
  }

  smsMessageErrors() {
    const { errorsByPath } = this.props
    return errorsByPath['mobileWebSmsMessage']
  }

  surveyIsOverMessageErrors() {
    const { errorsByPath } = this.props
    return errorsByPath['mobileWebSurveyIsOverMessage']
  }

  surveyAlreadyTakenMessageErrors() {
    const { questionnaire, errorsByPath } = this.props
    return errorsByPath[`surveyAlreadyTakenMessage['${questionnaire.activeLanguage}']`]
  }

  hasErrors() {
    return !!this.messageErrors('quotaCompletedMessage') ||
      !!this.messageErrors('errorMessage') ||
      !!this.messageErrors('thankYouMessage') ||
      !!this.titleErrors() ||
      !!this.smsMessageErrors() ||
      !!this.surveyIsOverMessageErrors() ||
      !!this.surveyAlreadyTakenMessageErrors()
  }

  render() {
    const { questionnaire } = this.props
    if (!questionnaire) {
      return <div>Loading...</div>
    }

    if (this.state.editing) {
      return this.expanded()
    } else {
      return this.collapsed()
    }
  }
}

WebSettings.propTypes = {
  dispatch: PropTypes.any,
  questionnaire: PropTypes.object,
  errorsByPath: PropTypes.object,
  quotaCompletedMessage: PropTypes.string,
  errorMessage: PropTypes.string,
  thankYouMessage: PropTypes.string,
  title: PropTypes.string,
  smsMessage: PropTypes.string,
  surveyIsOverMessage: PropTypes.string,
  surveyAlreadyTakenMessage: PropTypes.string,
  readOnly: PropTypes.bool
}

const mapStateToProps = (state, ownProps) => {
  const quiz = state.questionnaire
  return {
    questionnaire: quiz.data,
    errorsByPath: quiz.errorsByPath,
    quotaCompletedMessage: quiz.data ? getPromptMobileWeb(quiz.data.settings.quotaCompletedMessage, quiz.data.activeLanguage) : '',
    errorMessage: quiz.data ? getPromptMobileWeb(quiz.data.settings.errorMessage, quiz.data.activeLanguage) : '',
    thankYouMessage: quiz.data ? getPromptMobileWeb(quiz.data.settings.thankYouMessage, quiz.data.activeLanguage) : '',
    title: quiz.data ? (quiz.data.settings.title || {})[quiz.data.activeLanguage] || '' : '',
    smsMessage: quiz.data ? quiz.data.settings.mobileWebSmsMessage || '' : '',
    surveyIsOverMessage: quiz.data ? quiz.data.settings.mobileWebSurveyIsOverMessage || '' : '',
    surveyAlreadyTakenMessage: quiz.data ? (quiz.data.settings.surveyAlreadyTakenMessage || {})[quiz.data.activeLanguage] || '' : ''
  }
}

export default connect(mapStateToProps)(WebSettings)
