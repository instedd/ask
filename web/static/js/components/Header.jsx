import React from 'react'
import { Link } from 'react-router'
import TitleContainer from '../containers/TitleContainer'
import { Dropdown, DropdownItem, DropdownDivider } from './Dropdown'
import * as routes from '../routes'

export default ({ tabs, logout, user, project }) => {
  let projectLink
  if (project) {
    projectLink = (
      <li>
        <Link to={routes.project(project.id)} className=''> {project.name} </Link>
      </li>
    )
  }

  return (
    <header>
      <nav id='TopNav'>
        <div className='nav-wrapper'>
          <div className='row'>
            <div className='col s5 m4'>
              <ul>
                <li>
                  <Link to={routes.projects} className=''> Projects </Link>
                </li>
                { projectLink }
                <li>
                  <Link to={routes.channels} className=''> Channels </Link>
                </li>
              </ul>
            </div>
            <div className='col s8 m8'>
              <ul className='right'>
                <li>
                  <Dropdown text={user}>
                    {/* <DropdownItem><Link to='#'>Settings</Link></DropdownItem> */}
                    <DropdownDivider />
                    <DropdownItem>
                      <a onClick={logout}>Logout</a>
                    </DropdownItem>
                  </Dropdown>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </nav>
      <TitleContainer />
      {tabs}
    </header>
  )
}
