import React, { PropTypes, Component } from 'react'
import merge from 'lodash/merge'
import { Link } from 'react-router'
import * as routes from '../../routes'

class ProjectForm extends Component {
  render() {
    const { onSubmit, project } = this.props

    if (!project) {
      return <div>Loading...</div>
    }

    return (
      <div>
        <div>
          <label>Project Name</label>
          <div>
            <input type='text' placeholder='Project name' value={project.name} ref='input' />
          </div>
        </div>
        <br />
        <div>
          <button type='button' onClick={() =>
            onSubmit(merge({}, project, { name: this.refs.input.value }))
          }>
            Submit
          </button>
          <Link to={routes.projects}> Back</Link>
        </div>
      </div>
    )
  }
}

ProjectForm.propTypes = {
  onSubmit: PropTypes.func.isRequired,
  project: PropTypes.object
}

export default ProjectForm
