import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule],
  template: `
    <h1>News UI (Angular)</h1>
    <p>API health via UI proxy:</p>
    <pre>{{ health | json }}</pre>
  `
})
export class AppComponent {
  health: any = { loading: true };
  constructor(){
    fetch('/api/healthz').then(r => r.json()).then(j => this.health = j).catch(e => this.health = { error: String(e) });
  }
}
