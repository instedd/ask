// @flow
import React, { Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import StepTypeSelector from './StepTypeSelector'
import * as questionnaireActions from '../../actions/questionnaire'
import StepPrompts from './StepPrompts'
import StepCard from './StepCard'
import DraggableStep from './DraggableStep'
import StepDeleteButton from './StepDeleteButton'
import SkipLogic from './SkipLogic'
import propsAreEqual from '../../propsAreEqual'

type Props = {
  step: ExplanationStep,
  stepIndex: number,
  questionnaireActions: any,
  onDelete: Function,
  onCollapse: Function,
  questionnaire: Questionnaire,
  errorPath: string,
  errorsByPath: ErrorsByPath,
  readOnly: boolean,
  quotaCompletedSteps: boolean,
  stepsAfter: Step[],
  stepsBefore: Step[]
};

type State = {
  stepTitle: string,
  stepType: string,
  stepPromptSms: string,
  stepPromptIvr: string,
  skipLogic: ?string
};

class ExplanationStepEditor extends Component {
  props: Props
  state: State

  constructor(props) {
    super(props)
    this.state = this.stateFromProps(props)
  }

  componentWillReceiveProps(newProps) {
    if (propsAreEqual(this.props, newProps)) return

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
      skipLogic: step.skipLogic
    }
  }

  skipLogicChange(skipOption, rangeIndex) {
    const { questionnaireActions, step } = this.props

    this.setState({ skipLogic: skipOption }, () => {
      questionnaireActions.changeExplanationStepSkipLogic(step.id, skipOption)
    })
  }

  render() {
    const { step, stepIndex, onCollapse, stepsAfter, stepsBefore, onDelete, errorPath, errorsByPath, readOnly, quotaCompletedSteps } = this.props

    return (
      <DraggableStep step={step} readOnly={readOnly} quotaCompletedSteps={quotaCompletedSteps}>
        <StepCard onCollapse={onCollapse} readOnly={readOnly} stepId={step.id} stepTitle={this.state.stepTitle} icon={<StepTypeSelector stepType={step.type} stepId={step.id} readOnly={readOnly} quotaCompletedSteps={quotaCompletedSteps} />} >
          <StepPrompts
            step={step}
            readOnly={readOnly}
            stepIndex={stepIndex}
            errorPath={errorPath}
            errorsByPath={errorsByPath}
            classes='no-separator'
            title='Message'
          />
          <li className='collection-item' key='editor'>
            <div className='row'>
              <div className='col s6'>
                <SkipLogic
                  onChange={skipOption => this.skipLogicChange(skipOption)}
                  readOnly={readOnly}
                  value={step.skipLogic}
                  stepsAfter={stepsAfter}
                  stepsBefore={stepsBefore}
                  label='Skip logic'
                />
              </div>
            </div>
          </li>
          {readOnly ? null : <StepDeleteButton onDelete={onDelete} /> }
        </StepCard>
      </DraggableStep>
    )
  }
}

const mapStateToProps = (state, ownProps) => ({
  questionnaire: state.questionnaire.data
})

const mapDispatchToProps = (dispatch) => ({
  questionnaireActions: bindActionCreators(questionnaireActions, dispatch)
})

export default connect(mapStateToProps, mapDispatchToProps)(ExplanationStepEditor)
