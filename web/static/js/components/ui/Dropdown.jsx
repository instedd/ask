import { uniqueId } from 'lodash'
import React, { Component, PropTypes } from 'react'
export class Dropdown extends Component {
  static propTypes = {
    label: PropTypes.node.isRequired,
    icon: PropTypes.string,
    iconLeft: PropTypes.bool,
    children: PropTypes.node,
    constrainWidth: PropTypes.bool,
    readOnly: PropTypes.bool,
    dataBelowOrigin: PropTypes.bool,
    className: PropTypes.string,
    onInitHook: PropTypes.func
  }

  constructor(props) {
    super(props)
    this.dropdownId = uniqueId('dropdown')
  }

  componentDidMount() {
    const {readOnly, onInitHook} = this.props
    if (!readOnly) $(this.refs.node).dropdown()
    if (onInitHook) onInitHook()
  }

  render() {
    const { label, icon = 'arrow_drop_down', dataBelowOrigin = true, children, constrainWidth = true, className, readOnly, iconLeft = false } = this.props
    const onButtonClick = (event) => {
      event.preventDefault()
    }

    return (
      <span className={className}>
        <a className='dropdown-button' href='#!' onClick={onButtonClick} data-induration='100' data-outduration='50' data-beloworigin={dataBelowOrigin} data-activates={this.dropdownId} data-constrainwidth={constrainWidth} ref='node'>
          {label}
          {readOnly ? null : <i className={iconLeft ? 'material-icons left' : 'material-icons right'}>{icon}</i> }
        </a>
        <ul id={this.dropdownId} className='dropdown-content'>
          {children}
        </ul>
      </span>
    )
  }
}

export const DropdownItem = ({children, className}) => (
  <li className={className}>{children}</li>
)

DropdownItem.propTypes = {
  children: PropTypes.node,
  className: PropTypes.string
}

export const DropdownDivider = () => (
  <li className='divider' />
)
