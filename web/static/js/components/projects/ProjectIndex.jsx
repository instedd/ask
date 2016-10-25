import React, { Component, PropTypes } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import { createProject } from '../../api'
import * as actions from '../../actions/projects'
import * as projectActions from '../../actions/project'
import { AddButton, EmptyPage, CardTable, SortableHeader, UntitledIfEmpty } from '../ui'
import * as routes from '../../routes'
import range from 'lodash/range'
import { orderedItems } from '../../dataTable'

class ProjectIndex extends Component {
  componentWillMount() {
    this.creatingProject = false

    this.props.projectActions.clearProject()
    this.props.actions.fetchProjects()
  }

  newProject(e) {
    e.preventDefault()

    // Prevent multiple clicks to create multiple projects
    if (this.creatingProject) return
    this.creatingProject = true

    const { router } = this.props

    let theProject
    createProject({name: ''})
        .then(response => {
          theProject = response.entities.projects[response.result]
          this.props.projectActions.createProject(theProject)
        })
        .then(() => {
          this.creatingProject = false
          router.push(routes.project(theProject.id))
        })
  }

  nextPage(e) {
    e.preventDefault()
    this.props.actions.nextProjectsPage()
  }

  previousPage(e) {
    e.preventDefault()
    this.props.actions.previousProjectsPage()
  }

  sortBy(property) {
    this.props.actions.sortProjectsBy(property)
  }

  render() {
    const { projects, sortBy, sortAsc, pageSize, startIndex, endIndex,
      totalCount, hasPreviousPage, hasNextPage, router } = this.props

    if (!projects) {
      return (
        <div>
          <CardTable title='Loading projects...' highlight />
        </div>
      )
    }

    const title = `${totalCount} ${(totalCount === 1) ? ' project' : ' projects'}`
    const footer = (
      <div className='right-align'>
        <ul className='pagination'>
          <li><span className='grey-text'>{startIndex}-{endIndex} of {totalCount}</span></li>
          { hasPreviousPage
            ? <li><a href='#!' onClick={e => this.previousPage(e)}><i className='material-icons'>chevron_left</i></a></li>
            : <li className='disabled'><i className='material-icons'>chevron_left</i></li>
          }
          { hasNextPage
            ? <li><a href='#!' onClick={e => this.nextPage(e)}><i className='material-icons'>chevron_right</i></a></li>
            : <li className='disabled'><i className='material-icons'>chevron_right</i></li>
          }
        </ul>
      </div>
    )

    return (
      <div>
        <AddButton text='Add project' onClick={e => this.newProject(e)} />
        { (projects.length === 0)
          ? <EmptyPage icon='assignment_turned_in' title='You have no projects yet' linkPath={routes.newProject} />
          : <CardTable title={title} footer={footer} highlight>
            <thead>
              <tr>
                <SortableHeader text='Name' property='name' sortBy={sortBy} sortAsc={sortAsc} onClick={(name) => this.sortBy(name)} />
              </tr>
            </thead>
            <tbody>
              { range(0, pageSize).map(index => {
                const project = projects[index]
                if (!project) return <tr key={index}><td>&nbsp;</td></tr>

                return (
                  <tr key={index}>
                    <td onClick={() => router.push(routes.project(project.id))}>
                      <UntitledIfEmpty text={project.name} />
                    </td>
                  </tr>
                ) })
              }
            </tbody>
          </CardTable>
        }
      </div>
    )
  }
}

ProjectIndex.propTypes = {
  actions: PropTypes.object.isRequired,
  projectActions: PropTypes.object.isRequired,
  sortBy: PropTypes.string,
  sortAsc: PropTypes.bool.isRequired,
  projects: PropTypes.array,
  pageSize: PropTypes.number.isRequired,
  startIndex: PropTypes.number.isRequired,
  endIndex: PropTypes.number.isRequired,
  hasPreviousPage: PropTypes.bool.isRequired,
  hasNextPage: PropTypes.bool.isRequired,
  totalCount: PropTypes.number.isRequired,
  router: PropTypes.object
}

const mapStateToProps = (state) => {
  let projects = orderedItems(state.projects.items, state.projects.order)
  const sortBy = state.projects.sortBy
  const sortAsc = state.projects.sortAsc
  const totalCount = projects ? projects.length : 0
  const pageIndex = state.projects.page.index
  const pageSize = state.projects.page.size
  if (projects) {
    projects = projects.slice(pageIndex, pageIndex + pageSize)
  }
  const startIndex = Math.min(totalCount, pageIndex + 1)
  const endIndex = Math.min(pageIndex + pageSize, totalCount)
  const hasPreviousPage = startIndex > 1
  const hasNextPage = endIndex < totalCount
  return {
    sortBy,
    sortAsc,
    projects,
    pageSize,
    startIndex,
    endIndex,
    hasPreviousPage,
    hasNextPage,
    totalCount
  }
}

const mapDispatchToProps = (dispatch) => ({
  actions: bindActionCreators(actions, dispatch),
  projectActions: bindActionCreators(projectActions, dispatch)
})

export default withRouter(connect(mapStateToProps, mapDispatchToProps)(ProjectIndex))
