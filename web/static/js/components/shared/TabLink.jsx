import React from 'react'
import { withRouter } from 'react-router'

export default withRouter(props => {
  const { children, to, router } = props
  const className = router.isActive(to) ? 'active' : ''
  const clickHandler = () => {
    router.push(to)
  }

  return (
    <li className='tab col'>
      <a onClick={clickHandler} className={className}>{children}</a>
    </li>
  )
})
