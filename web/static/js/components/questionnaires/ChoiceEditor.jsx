// @flow
import React, { Component } from 'react'
import { UntitledIfEmpty, Tooltip, Autocomplete } from '../ui'
import classNames from 'classnames/bind'
import SkipLogic from './SkipLogic'
import { getChoiceResponseSmsJoined, getChoiceResponseIvrJoined, getChoiceResponseMobileWebJoined } from '../../step'
import propsAreEqual from '../../propsAreEqual'
import map from 'lodash/map'
import { translate } from 'react-i18next'

type Props = {
  onDelete: Function,
  onChoiceChange: Function,
  choice: Choice,
  choiceIndex: any,
  readOnly: boolean,
  stepIndex: number,
  stepsBefore: Step[],
  stepsAfter: Step[],
  lang: string,
  sms: boolean,
  mobileweb: boolean,
  ivr: boolean,
  errorPath: string,
  errorsByPath: ErrorsByPath,
  t: Function,
  smsAutocompleteGetData: Function,
  smsAutocompleteOnSelect: Function,
  isNew: boolean,
  responseAutocompleteGetData: Function
};

type Focus = null | 'response' | 'sms' | 'ivr' | 'mobileweb';

type State = {
  response: string,
  sms: string,
  ivr: string,
  mobileweb: string,
  editing: boolean,
  focus: Focus,
  doNotClose: boolean,
  skipLogic: ?string,
};

class ChoiceEditor extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { ...this.stateFromProps(props), editing: false, doNotClose: false, focus: null, errors: null }
  }

  responseChange(event: Event) {
    event.preventDefault()
    if (event.target instanceof HTMLInputElement) {
      this.setState({
        ...this.state,
        response: event.target.value
      })
    }
  }

  smsChange(event: ?SyntheticEvent<>, sms: string) {
    if (event) event.preventDefault()
    this.setState({
      ...this.state,
      sms
    })
  }

  mobilewebChange(event: ?Event, mobileweb: string) {
    if (event) event.preventDefault()
    this.setState({
      ...this.state,
      mobileweb
    })
  }

  ivrChange(event: Event) {
    event.preventDefault()
    if (event.target instanceof HTMLInputElement) {
      this.setState({
        ...this.state,
        ivr: event.target.value
      })
    }
  }

  componentWillReceiveProps(newProps: Props) {
    if (propsAreEqual(this.props, newProps)) return

    let newState = this.stateFromProps(newProps)
    this.setState({ ...newState, editing: this.state.editing })
  }

  stateFromProps(props: Props) {
    const { choice, lang } = props

    return {
      response: choice.value,
      sms: getChoiceResponseSmsJoined(choice, lang),
      ivr: getChoiceResponseIvrJoined(choice),
      mobileweb: getChoiceResponseMobileWebJoined(choice, lang),
      skipLogic: choice.skipLogic
    }
  }

  enterEditMode(event: ?Event, focus: Focus) {
    if (event) event.preventDefault()

    const {readOnly} = this.props
    if (!readOnly) {
      this.setState({
        ...this.state,
        editing: true,
        focus: focus
      })
    }
  }

  exitEditMode(autoComplete: boolean = false) {
    let autocomplete = this.refs.autocomplete
    if (autocomplete && autocomplete.clickingAutocomplete) return

    const { onChoiceChange } = this.props
    if (this.state.doNotClose) {
      this.state.doNotClose = false
      if (autoComplete) {
        onChoiceChange(this.state.response, this.state.sms, this.state.ivr, this.state.mobileweb, this.state.skipLogic, true)
      }
    } else {
      this.setState({
        ...this.state,
        editing: false
      }, () => {
        onChoiceChange(this.state.response, this.state.sms, this.state.ivr, this.state.mobileweb, this.state.skipLogic, autoComplete)
      })
    }
  }

  autoComplete(event: Event) {
    this.exitEditMode(true)
  }

  setDoNotClose(focus: Focus) {
    if (this.state.focus != focus) {
      this.state.doNotClose = true
      this.state.focus = focus
    }
  }

  onKeyDown(event: SyntheticKeyboardEvent<any>, focus: Focus, autoComplete: boolean = false) {
    if (event.key == 'Enter') {
      event.preventDefault()
      this.exitEditMode(autoComplete)
    } else if (event.key == 'Tab') {
      this.setDoNotClose(focus)
    }
  }

  smsCheckEmptyString(event: SyntheticEvent<HTMLInputElement>) {
    // This is due to a materialize css bug. Analogous to SmsPrompt
    if (!event.currentTarget.value) {
      this.smsChange(event, '')
    }
  }

  skipLogicChange(skipOption: ?string) {
    const { onChoiceChange } = this.props
    this.setState({
      ...this.state,
      skipLogic: skipOption
    }, () => {
      onChoiceChange(this.state.response, this.state.sms, this.state.ivr, this.state.mobileweb, this.state.skipLogic)
    })
  }

  maybeTooltip(shouldWrap: any, elem: any, tooltipText: string) {
    if (shouldWrap) {
      return (
        <Tooltip text={tooltipText} position='bottom' className='error'>
          {elem}
        </Tooltip>
      )
    } else {
      return elem
    }
  }

  cell(value: string, errors: ?string[], shouldDisplay: boolean, onClick: Function) {
    const { isNew, t } = this.props

    const tooltip = (map(errors, (error) => t(...error)) || [value]).join(', ')

    const elem = shouldDisplay
      ? <div>
        <UntitledIfEmpty
          text={value}
          emptyText={'\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0'}
          className={classNames({'basic-error': errors, 'isNew-error': isNew && (!value || value.trim().length == 0)})} />
      </div>
    : null

    return shouldDisplay
    ? <td onClick={onClick}>
      {this.maybeTooltip(errors, elem, tooltip)}
    </td> : null
  }

  render() {
    const { onDelete, stepsBefore, stepsAfter, readOnly, choiceIndex, sms, ivr, mobileweb, errorPath, errorsByPath, isNew, lang, smsAutocompleteGetData, responseAutocompleteGetData, smsAutocompleteOnSelect, t } = this.props

    const isRefusal = choiceIndex == 'refusal'

    let skipLogicInput =
      <td className='skipLogic'>
        <SkipLogic
          onChange={skipOption => this.skipLogicChange(skipOption)}
          readOnly={readOnly}
          value={this.state.skipLogic}
          errorPath={`${errorPath}[${choiceIndex}].skipLogic`}
          errorsByPath={errorsByPath}
          stepsAfter={stepsAfter}
          stepsBefore={stepsBefore}
          />
      </td>

    if (this.state.editing) {
      return (
        <tr>
          {!isRefusal
          ? <td onMouseDown={e => this.setDoNotClose('response')}>
            <input
              type='text'
              ref='responseInput'
              placeholder={t('Response')}
              value={this.state.response}
              autoFocus={this.state.focus == 'response'}
              onChange={e => this.responseChange(e)}
              onBlur={e => this.autoComplete(e)}
              onKeyDown={e => this.onKeyDown(e, 'sms', true)}
              draggable
              onDragStart={e => { e.stopPropagation(); e.preventDefault(); return false }}
              />
            <Autocomplete
              getInput={() => this.refs.responseInput}
              getData={(value, callback) => responseAutocompleteGetData(value, callback)}
              onSelect={(item) => {
                // TODO: Honor the user selection
              }}
              ref='autocomplete'
            />
          </td>

          : null }
          { sms
          ? <td onMouseDown={e => this.setDoNotClose('sms')}>
            <input
              type='text'
              ref='smsInput'
              placeholder={t('Valid entries')}
              value={this.state.sms}
              autoFocus={this.state.focus == 'sms'}
              onChange={e => this.smsChange(e, e.target.value)}
              onBlur={e => this.exitEditMode()}
              onKeyUp={e => this.smsCheckEmptyString(e)}
              onKeyDown={e => this.onKeyDown(e, 'ivr')}
              draggable
              onDragStart={e => { e.stopPropagation(); e.preventDefault(); return false }}
              />
            <Autocomplete
              getInput={() => this.refs.smsInput}
              getData={(value, callback) => smsAutocompleteGetData(value, callback)}
              onSelect={(item) => smsAutocompleteOnSelect(item)}
              ref='autocomplete'
              />
          </td> : null
          }
          { ivr
          ? <td onMouseDown={e => this.setDoNotClose('ivr')}>
            <input
              type='text'
              placeholder={t('Valid entries')}
              value={this.state.ivr}
              autoFocus={this.state.focus == 'ivr'}
              onChange={e => this.ivrChange(e)}
              onBlur={e => this.exitEditMode()}
              onKeyDown={e => this.onKeyDown(e, 'mobileweb')}
              draggable
              onDragStart={e => { e.stopPropagation(); e.preventDefault(); return false }}
              />
          </td> : null
          }
          {
            mobileweb
          ? <td onMouseDown={e => this.setDoNotClose('mobileweb')}>
            <input
              type='text'
              placeholder={t('Valid entries')}
              value={this.state.mobileweb}
              autoFocus={this.state.focus == 'mobileweb'}
              onChange={e => this.mobilewebChange(e, e.target.value)}
              onBlur={e => this.exitEditMode()}
              onKeyDown={e => this.onKeyDown(e, null)}
              draggable
              onDragStart={e => { e.stopPropagation(); e.preventDefault(); return false }}
              />
          </td> : null
          }
          {skipLogicInput}
          { (!isRefusal)
          ? <td className='tdDelete'>
            <a href='#!' onFocus={e => this.exitEditMode()} onClick={onDelete}><i className='material-icons grey-text'>delete</i></a>
          </td> : null
          }
        </tr>)
    } else {
      const path = `${errorPath}[${choiceIndex}]`

      let responseErrors = null
      let smsErrors = null
      let ivrErrors = null
      let mobilewebErrors = null

      if (!isNew) {
        responseErrors = !isRefusal ? errorsByPath[`${path}.value`] : []
        smsErrors = errorsByPath[`${path}['${lang}'].sms`]
        ivrErrors = errorsByPath[`${path}.ivr`]
        mobilewebErrors = errorsByPath[`${path}['${lang}'].mobileweb`]
      }

      return (
        <tr>
          {!isRefusal
          ? this.cell(this.state.response, responseErrors, true, e => this.enterEditMode(e, 'response'))
          : null
          }
          {this.cell(this.state.sms, smsErrors, sms, e => this.enterEditMode(e, 'sms'))}
          {this.cell(this.state.ivr, ivrErrors, ivr, e => this.enterEditMode(e, 'ivr'))}
          {this.cell(this.state.mobileweb, mobilewebErrors, mobileweb, e => this.enterEditMode(e, 'mobileweb'))}
          {skipLogicInput}
          { readOnly || isRefusal ? <td />
            : <td className='tdDelete'>
              <a href='#!' onClick={onDelete}><i className='material-icons grey-text'>delete</i></a>
            </td>
          }
        </tr>
      )
    }
  }

  static fromRef(ref): ChoiceEditor {
    return ref.getWrappedInstance()
  }
}

export default translate(null, {withRef: true})(ChoiceEditor)
