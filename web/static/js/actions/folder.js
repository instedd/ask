import * as api from '../api'

export const FETCH_FOLDERS = 'FETCH_FOLDERS'
export const FETCHING_FOLDERS = 'FETCHING_FOLDERS'
export const FETCHED_FOLDERS = 'FETCHED_FOLDERS'
export const FETCH_FOLDER = 'FETCH_FOLDER'
export const FETCHING_FOLDER = 'FETCHING_FOLDER'
export const FETCHED_FOLDER = 'FETCHED_FOLDER'
export const CREATE_FOLDER = 'FOLDER_CREATE'
export const DELETE_FOLDER = 'FOLDER_DELETE'
export const SAVING_FOLDER = 'FOLDER_SAVING'
export const DELETING_FOLDER = 'FOLDER_DELETING'
export const NOT_SAVED_FOLDER = 'NOT_SAVED_FOLDER'
export const SAVED_FOLDER = 'FOLDER_SAVED'
export const DELETED_FOLDER = 'FOLDER_DELETED'
export const NOT_DELETED_FOLDER = 'NOT_DELETED_FOLDER'

export const createFolder = (projectId: number, name: string) => (dispatch: Function) => {
  dispatch(savingFolder())
  return api.createFolder(projectId, name)
    .then(res => {
      dispatch(savedFolder())
      return res
    })
    .catch(async res => {
      const errors = await res.json()
      dispatch(notSavedFolder(errors))
      return errors
    })
}

export const deleteFolder = (projectId: number, folderId: number) => (dispatch: Function) => {
  dispatch(deletingFolder())
  return api.deleteFolder(projectId, folderId)
    .then(res => {
      dispatch(deletedFolder(folderId))
    })
    .catch(async res => {
      dispatch(notDeletedFolder())
    })
}

export const deletedFolder = id => {
  return {
    type: DELETED_FOLDER,
    id: id
  }
}

export const deletingFolder = () => {
  return {
    type: DELETING_FOLDER
  }
}

export const notDeletedFolder = () => {
  return {
    type: NOT_DELETED_FOLDER
  }
}

export const savingFolder = (projectId: number) => {
  return {
    type: SAVING_FOLDER
  }
}

export const savedFolder = (projectId: number) => {
  return {
    type: SAVED_FOLDER
  }
}

export const notSavedFolder = ({errors}) => {
  return {
    type: NOT_SAVED_FOLDER,
    errors
  }
}

export const fetchFolder = (projectId: number, folderId: number) => (dispatch: Function) => {
  dispatch(fetchingFolder())

  return api.fetchFolder(projectId, folderId)
    .then(response => {
      dispatch(fetchedFolder(projectId, folderId, response.entities.folders[response.result]))
    })
}

export const fetchingFolder = (folderId: number) => {
  return {
    type: FETCHING_FOLDER
  }
}

export const fetchedFolder = (projectId, folderId, folder) => {
  return {
    type: FETCHED_FOLDER,
    folderId,
    folder
  }
}

export const fetchFolders = (projectId: number) => (dispatch: Function) => {
  dispatch(fetchingFolders())

  return api.fetchFolders(projectId)
    .then(response => {
      dispatch(fetchedFolders(projectId, response.entities.folders))
    })
}

export const fetchingFolders = (projectId: number) => {
  return {
    type: FETCHING_FOLDERS
  }
}

export const fetchedFolders = (projectId: number, folders) => {
  return {
    type: FETCHED_FOLDERS,
    projectId,
    folders
  }
}
