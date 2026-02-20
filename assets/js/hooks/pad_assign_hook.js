const PadAssignHook = {
  mounted() {
    this.setupDragAndDrop();
  },
  updated() {
    this.setupDragAndDrop();
  },
  setupDragAndDrop() {
    // Make stem items draggable
    this.el.querySelectorAll('[data-stem-drag]').forEach(item => {
      item.setAttribute('draggable', true);
      item.addEventListener('dragstart', (e) => {
        e.dataTransfer.setData('text/plain', item.dataset.stemDrag);
        e.dataTransfer.effectAllowed = 'copy';
        item.classList.add('opacity-50');
      });
      item.addEventListener('dragend', (e) => {
        item.classList.remove('opacity-50');
      });
      // Touch support
      item.addEventListener('touchstart', (e) => {
        this.dragItem = item.dataset.stemDrag;
        item.classList.add('opacity-50');
      }, {passive: true});
    });

    // Make pad cells drop targets
    this.el.querySelectorAll('[data-pad-drop]').forEach(pad => {
      pad.addEventListener('dragover', (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'copy';
        pad.classList.add('ring-2', 'ring-purple-500');
      });
      pad.addEventListener('dragleave', (e) => {
        pad.classList.remove('ring-2', 'ring-purple-500');
      });
      pad.addEventListener('drop', (e) => {
        e.preventDefault();
        pad.classList.remove('ring-2', 'ring-purple-500');
        const stemId = e.dataTransfer.getData('text/plain');
        this.pushEvent('assign_pad', {pad: pad.dataset.padDrop, stem_id: stemId});
      });
      // Touch support
      pad.addEventListener('touchend', (e) => {
        if (this.dragItem) {
          this.pushEvent('assign_pad', {pad: pad.dataset.padDrop, stem_id: this.dragItem});
          this.dragItem = null;
          this.el.querySelectorAll('[data-stem-drag]').forEach(i => i.classList.remove('opacity-50'));
        }
      }, {passive: true});
    });
  }
};
export default PadAssignHook;
