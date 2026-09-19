import { Button } from "../../components/Button";
import { detailModel } from "./model";
import type { Model } from "../../types/models";
import { DUAL } from '../../lib/dual';

export function DetailView({ model }: { model: Model }) {
  return (
    <section data-doc="https://example.com/docs/import/from/lib/format">
      {/* import { Card } from "../../widgets/Card.jsx" - removed, see #412 */}
      <Button
        label={detailModel(model).text + DUAL}
        onClick={async () => "ok"}
      />
    </section>
  );
}
