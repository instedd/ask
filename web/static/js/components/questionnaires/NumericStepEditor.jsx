// @flow
import React, { Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import StepTypeSelector from './StepTypeSelector'
import * as questionnaireActions from '../../actions/questionnaire'
import StepPrompts from './StepPrompts'
import StepCard from './StepCard'
import StepNumericEditor from './StepNumericEditor'
import { autocompleteVars } from '../../api.js'
import DraggableStep from './DraggableStep'
import StepDeleteButton from './StepDeleteButton'

type Props = {
  step: Step,
  questionnaireActions: any,
  onDelete: Function,
  onCollapse: Function,
  questionnaire: Questionnaire,
  project: any,
  errors: any,
  errorPath: string,
  stepsAfter: Step[],
  stepsBefore: Step[]
};

type State = {
  stepTitle: string,
  stepType: string,
  stepPromptSms: string,
  stepPromptIvr: string,
  stepStore: string
};

class NumericStepEditor extends Component {
  props: Props
  state: State
  clickedVarAutocomplete: boolean

  constructor(props) {
    super(props)
    this.state = this.stateFromProps(props)
    this.clickedVarAutocomplete = false
  }

  stepStoreChange(e, value) {
    if (this.clickedVarAutocomplete) return
    if (e) e.preventDefault()
    this.setState({stepStore: value})
  }

  stepStoreSubmit(e, value) {
    if (this.clickedVarAutocomplete) return
    const varsDropdown = this.refs.varsDropdown
    $(varsDropdown).hide()

    if (e) e.preventDefault()
    const { step } = this.props
    this.props.questionnaireActions.changeStepStore(step.id, value)
  }

  componentWillReceiveProps(newProps) {
    this.setState(this.stateFromProps(newProps))
  }

  stateFromProps(props) {
    const { step } = props
    const lang = props.questionnaire.defaultLanguage

    return {
      stepTitle: step.title,
      stepType: step.type,
      stepPromptSms: (step.prompt[lang] || {}).sms || '',
      stepPromptIvr: ((step.prompt[lang] || {}).ivr || {}).text || '',
      stepStore: step.store || ''
    }
  }

  clickedVarAutocompleteCallback(e) {
    this.clickedVarAutocomplete = true
  }

  render() {
    const { step, onCollapse, questionnaire, stepsAfter, stepsBefore, onDelete } = this.props

    const sms = questionnaire.modes.indexOf('sms') != -1
    const ivr = questionnaire.modes.indexOf('ivr') != -1

    let editor =
      <StepNumericEditor
        questionnaire={questionnaire}
        step={step}
        stepsAfter={stepsAfter}
        stepsBefore={stepsBefore} />

    let prompts = <StepPrompts stepPrompt={step.prompt[this.props.questionnaire.defaultLanguage]} stepId={step.id} sms={sms} ivr={ivr} />

    let optionsEditor = <li className='collection-item' key='editor'>
      <div className='row'>
        <div className='col s12'>
          {editor}
        </div>
      </div>
    </li>

    let variableName = <li className='collection-item' key='variable_name'>
      <div className='row'>
        <div className='col s12'>
          Variable name:
          <div className='input-field inline'>
            <input
              type='text'
              value={this.state.stepStore}
              onChange={e => this.stepStoreChange(e, e.target.value)}
              onBlur={e => this.stepStoreSubmit(e, e.target.value)}
              autoComplete='off'
              className='autocomplete'
              ref='varInput'
            />
            <ul className='autocomplete-content dropdown-content var-dropdown'
              ref='varsDropdown'
              onMouseDown={(e) => this.clickedVarAutocompleteCallback(e)}
            />
          </div>
        </div>
      </div>
    </li>

    let deleteButton = <StepDeleteButton onDelete={onDelete} />

    let icon = <StepTypeSelector stepType={step.type} stepId={step.id} />

    return (
      <DraggableStep step={step}>
        <StepCard onCollapse={onCollapse} icon={icon} stepId={step.id} stepTitle={this.state.stepTitle} >
          {prompts}
          {optionsEditor}
          {variableName}
          {deleteButton}
        </StepCard>
      </DraggableStep>
    )
  }

  componentDidMount() {
    this.setupAutocomplete()
  }

  componentDidUpdate() {
    this.setupAutocomplete()
  }

  setupAutocomplete() {
    const self = this
    const varInput = this.refs.varInput
    const varsDropdown = this.refs.varsDropdown
    const { project } = this.props

    $(varInput).click(() => $(varsDropdown).show())

    $(varInput).materialize_autocomplete({
      limit: 100,
      multiple: {
        enable: false
      },
      dropdown: {
        el: varsDropdown,
        itemTemplate: '<li class="ac-item" data-id="<%= item.id %>" data-text=\'<%= item.text %>\'><%= item.text %></li>'
      },
      onSelect: (item) => {
        self.clickedVarAutocomplete = false
        self.stepStoreChange(null, item.text)
        self.stepStoreSubmit(null, item.text)
      },
      getData: (value, callback) => {
        autocompleteVars(project.id, value)
        .then(response => {
          callback(value, response.map(x => ({id: x, text: x})))
        })
      }
    })
  }
}

const mapStateToProps = (state, ownProps) => ({
  project: state.project.data,
  questionnaire: state.questionnaire.data,
  errors: state.questionnaire.errors
})

const mapDispatchToProps = (dispatch) => ({
  questionnaireActions: bindActionCreators(questionnaireActions, dispatch)
})

export default connect(mapStateToProps, mapDispatchToProps)(NumericStepEditor)
