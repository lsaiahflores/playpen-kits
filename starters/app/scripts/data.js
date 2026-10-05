// REALISTIC SAMPLE DATA — replace with the app's real data layer. Never ship an app of empty states:
// seed believable names, dates and numbers so every screen looks lived-in on first open.
const SAMPLE = {
  stats: [
    { label: 'Active projects', value: '12', delta: '+3 this month', up: true, trend: [4, 5, 5, 7, 8, 8, 10, 12] },
    { label: 'Tasks completed', value: '248', delta: '+18%', up: true, trend: [90, 110, 105, 150, 170, 190, 220, 248] },
    { label: 'Avg. response time', value: '2.4h', delta: '-12 min', up: true, trend: [3.1, 3.0, 2.9, 2.8, 2.7, 2.6, 2.5, 2.4] },
    { label: 'Open issues', value: '7', delta: '+2 today', up: false, trend: [4, 4, 5, 4, 5, 6, 5, 7] }
  ],
  items: [
    { id: 1, name: 'Spring launch campaign', owner: 'Maya Chen', status: 'In progress', due: 'Oct 14' },
    { id: 2, name: 'Customer interviews round 3', owner: 'Jordan Park', status: 'Done', due: 'Oct 02' },
    { id: 3, name: 'Pricing page redesign', owner: 'Sam Rivera', status: 'In progress', due: 'Oct 21' },
    { id: 4, name: 'Onboarding email series', owner: 'Priya Nair', status: 'Review', due: 'Oct 09' },
    { id: 5, name: 'Q4 roadmap review', owner: 'Alex Morgan', status: 'Planned', due: 'Nov 03' }
  ]
};
