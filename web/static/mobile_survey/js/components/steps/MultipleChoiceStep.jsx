import React, { Component, PropTypes } from 'react'
import Prompt from '../Prompt'

class MultipleChoiceStep extends Component {
  getValue() {
    return this.refs.select.value
  }

  render() {
    const { step } = this.props
    return (
      <div>
        <Prompt text={step.prompt} />
        <select ref='select'>
          {step.choices.map(choice => {
            return <option key={choice} value={choice}>{choice}</option>
          })}
        </select>
        <input className='btn block' type='submit' value='Next' />
      </div>
    )
  }
}

MultipleChoiceStep.propTypes = {
  step: PropTypes.object
}

export default MultipleChoiceStep

