export default {
  app: {
    name: 'TMS',
  },
  nav: {
    dashboard: 'Dashboard',
    projects: 'Projects',
    signOut:   'Sign out',
  },
  login: {
    title:    'Sign in',
    email:    'Email',
    password: 'Password',
    submit:   'Sign in',
    busy:     'Signing in…',
  },
  dashboard: {
    title:         'Dashboard',
    emptyState:    'Nothing here yet.',
    goToProjects:  'Go to projects →',
  },
  projects: {
    title:        'Projects',
    empty:        'No projects yet.',
    back:         '← Back',
    newProject:   '+ New project',
    promptName:   'Project name:',
    promptLang:   'Default source language (e.g. en, de, fr):',
    columns: {
      name:      'Name',
      slug:      'Slug',
      sourceLang:'Source lang',
      role:      'Your role',
    },
    notFound:  'Project not found.',
    members:   'Members',
    files:     'Files',
  },
  files: {
    empty:       'No files yet.',
    upload:      '+ Upload file',
    columns: {
      name:       'Name',
      format:     'Format',
      target:     'Target',
      status:     'Status',
      assignedTo: 'Assigned to',
      keys:       'Keys',
    },
    unassigned:  'Unassigned',
    promptFile:  'Choose file:',
    promptFormat:'Format (laravel|vue):',
    promptTarget:'Target language (e.g. fr, de):',
    uploading:   'Uploading…',
  },
  members: {
    role: {
      admin:      'admin',
      lead:       'lead',
      translator: 'translator',
    },
  },
  common: {
    loading:  'Loading…',
    error:    'Something went wrong.',
    forbidden:'You do not have access.',
  },
}
